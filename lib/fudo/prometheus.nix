{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.metrics.prometheus;

in {

  options.fudo.metrics.prometheus = with types; {
    enable = mkEnableOption "Fudo Prometheus Data-Gathering Server";

    service-discovery-dns = mkOption {
      type = attrsOf (listOf str);
      description = ''
        A map of exporter type to a list of domains to use for service discovery.
      '';
      example = {
        node = [ "node._metrics._tcp.my-domain.com" ];
        postfix = [ "postfix._metrics._tcp.my-domain.com" ];
      };
      default = {
        dovecot = [];
        node = [];
        postfix = [];
        rspamd = [];
      };
    };

    static-targets = mkOption {
      type = attrsOf (listOf str);
      description = ''
          A map of exporter type to a list of host:ports from which to collect metrics.
        '';
      example = {
        node = [ "my-host.my-domain:1111" ];
      };
      default = {
        dovecot = [];
        node = [];
        postfix = [];
        rspamd = [];
      };
    };

    docker-hosts = mkOption {
      type = listOf str;
      description = ''
        A list of explicit <host:port> docker targets from which to gather node data.
      '';
      default = [];
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
      default = "/var/lib/prometheus";
    };

    private-network = mkEnableOption "Network is private.";
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.state-directory} 0700 ${config.systemd.services.prometheus.serviceConfig.User} - - -"
    ];

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;

      virtualHosts = {
        "${cfg.hostname}" = {
          enableACME = ! cfg.private-network;
          forceSSL = ! cfg.private-network;

          locations."/" = {
            proxyPass = "http://127.0.0.1:9090";

            extraConfig = let
              local-networks = config.instance.local-networks;
            in "${optionalString ((length local-networks) > 0)
              (concatStringsSep "\n"
                (map (network: "allow ${network};") local-networks)) + "\ndeny all;"}";
          };
        };
      };
    };

    services.prometheus = {

      enable = true;

      webExternalUrl = "https://${cfg.hostname}";

      listenAddress = "127.0.0.1";
      port = 9090;

      scrapeConfigs = let
        make-job = type: {
          job_name = type;
          honor_labels = false;
          scheme = if cfg.private-network then "http" else "https";
          metrics_path = "/metrics/${type}";
          dns_sd_configs = if (hasAttr type cfg.service-discovery-dns) then
            [ { names = cfg.service-discovery-dns.${type}; } ] else [];
          static_configs = if (hasAttr type cfg.static-targets) then
            [ { targets = cfg.static-targets.${type}; } ] else [];
        };
      in map make-job ["docker" "node" "dovecot" "postfix" "rspamd"];

      pushgateway = {
        enable = if (cfg.push-url != null) then true else false;
        web = {
          external-url = if cfg.push-url == null then
            cfg.push-address
                         else
                           cfg.push-url;
          listen-address = cfg.push-address;
        };
      };
    };
  };
}
