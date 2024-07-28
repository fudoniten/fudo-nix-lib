{ config, lib, pkgs, ... }@toplevel:

with lib;
let cfg = config.fudo.metrics.prometheus;

in {

  options.fudo.metrics.prometheus = with types; {
    enable = mkEnableOption "Fudo Prometheus Data-Gathering Server";

    package = mkOption {
      type = package;
      default = pkgs.prometheus;
      defaultText = literalExpression "pkgs.prometheus";
      description = "The prometheus package that should be used.";
    };

    scrapers = let
      scraperOpts.options = {
        name = mkOption {
          type = str;
          description = "Name of this exporter.";
        };

        secured = mkOption {
          type = bool;
          description = "Whether to use https instead of http.";
          default = !toplevel.config.fudo.metrics.prometheus.private-network;
        };

        path = mkOption {
          type = str;
          description = "Host path at which to find exported metrics.";
          default = "/metrics";
        };

        port = mkOption {
          type = port;
          description = "Port on which to scrape for metrics.";
          default =
            if toplevel.config.fudo.metrics.prometheus.private-network then
              80
            else
              443;
        };

        static-targets = mkOption {
          type = listOf str;
          description = "Explicit list of hosts to scrape for metrics.";
          default = [ ];
        };

        dns-sd-records = mkOption {
          type = listOf str;
          description = "List of DNS records to query for hosts to scrape.";
          default = [ ];
        };
      };
    in mkOption {
      type = listOf (submodule scraperOpts);
      default = [ ];
    };

    docker-hosts = mkOption {
      type = listOf str;
      description = ''
        A list of explicit <host:port> docker targets from which to gather node data.
      '';
      default = [ ];
    };

    push-url = mkOption {
      type = nullOr str;
      description = ''
        The <host:port> that services can use to manually push data.
      '';
      default = null;
    };

    push-address = mkOption {
      type = nullOr str;
      description = ''
        The <host:port> address on which to listen for incoming data.
      '';
      default = null;
    };

    hostname = mkOption {
      type = str;
      description = "The hostname upon which Prometheus will serve.";
      example = "my-metrics-server.fudo.org";
    };

    state-directory = mkOption {
      type = str;
      description = "Directory at which to store Prometheus state.";
    };

    private-network = mkEnableOption "Network is private.";
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.state-directory} 0700 ${config.systemd.services.prometheus.serviceConfig.User} - - -"
    ];

    fileSystems =
      let state-dir = "/var/lib/${config.services.prometheus.stateDir}";
      in mkIf (cfg.state-directory != state-dir) {
        ${state-dir} = {
          device = cfg.state-directory;
          options = [ "bind" ];
        };
      };

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;

      virtualHosts = {
        "${cfg.hostname}" = {
          enableACME = !cfg.private-network;
          forceSSL = !cfg.private-network;

          locations."/" = {
            proxyPass = "http://127.0.0.1:9090";

            extraConfig = let local-networks = config.instance.local-networks;
            in "${optionalString ((length local-networks) > 0)
            (concatStringsSep "\n"
              (map (network: "allow ${network};") local-networks)) + ''

                deny all;''}";
          };
        };
      };
    };

    services.prometheus = {

      enable = true;
      webExternalUrl = "https://${cfg.hostname}";

      package = cfg.package;

      listenAddress = "127.0.0.1";
      port = 9090;

      scrapeConfigs = let
        mkScraper =
          { name, secured, path, port, static-targets, dns-sd-records }: {
            job_name = name;
            honor_labels = false;
            scheme = if secured then "https" else "http";
            metrics_path = path;
            static_configs =
              let attachPort = target: "${target}:${toString port}";
              in [{ targets = map attachPort static-targets; }];
            dns_sd_configs = [{ names = dns-sd-records; }];
          };
      in map mkScraper cfg.scrapers;

      pushgateway = {
        enable = if (cfg.push-url != null) then true else false;
        web = {
          external-url =
            if cfg.push-url == null then cfg.push-address else cfg.push-url;
          listen-address = cfg.push-address;
        };
      };
    };
  };
}
