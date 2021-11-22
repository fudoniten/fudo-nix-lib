{ config, lib, pkgs, ... }:

with lib;
let
  inherit (lib.strings) concatStringsSep;
  cfg = config.fudo.prometheus;

in {

  options.fudo.prometheus = {
    enable = mkEnableOption "Fudo Prometheus Data-Gathering Server";

    service-discovery-dns = mkOption {
      type = with types; attrsOf (listOf str);
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
      type = with types; attrsOf (listOf str);
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
      type = with types; listOf str;
      description = ''
        A list of explicit <host:port> docker targets from which to gather node data.
      '';
      default = [];
    };

    push-url = mkOption {
      type = with types; nullOr str;
      description = ''
        The <host:port> that services can use to manually push data.
      '';
      default = null;
    };

    push-address = mkOption {
      type = with types; nullOr str;
      description = ''
        The <host:port> address on which to listen for incoming data.
      '';
      default = null;
    };

    hostname = mkOption {
      type = with types; str;
      description = "The hostname upon which Prometheus will serve.";
      example = "my-metrics-server.fudo.org";
    };
  };

  config = mkIf cfg.enable {
    services.nginx = {
      enable = true;

      virtualHosts = {
        "${cfg.hostname}" = {
          enableACME = true;
          forceSSL = true;

          locations."/" = {
            proxyPass = "http://127.0.0.1:9090";

            extraConfig = let
              local-networks = config.instance.local-networks;
            in ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-By $server_addr:$server_port;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header X-Forwarded-Proto $scheme;

              ${optionalString ((length local-networks) > 0)
                (concatStringsSep "\n" (map (network: "allow ${network};") local-networks)) + "\ndeny all;"}
            '';
          };
        };
      };
    };

    services.prometheus = {

      enable = true;

      webExternalUrl = "https://${cfg.hostname}";

      listenAddress = "127.0.0.1";
      port = 9090;

      scrapeConfigs = [
        {
          job_name = "docker";
          honor_labels = false;
          static_configs = [
            {
              targets = cfg.docker-hosts;
            }
          ];
        }

        {
          job_name = "node";
          scheme = "https";
          metrics_path = "/metrics/node";
          honor_labels = false;
          dns_sd_configs = [
            {
              names = cfg.service-discovery-dns.node;
            }
          ];
          static_configs = [
            {
              targets = cfg.static-targets.node;
            }
          ];
        }

        {
          job_name = "dovecot";
          scheme = "https";
          metrics_path = "/metrics/dovecot";
          honor_labels = false;
          dns_sd_configs = [
            {
              names = cfg.service-discovery-dns.dovecot;
            }
          ];
          static_configs = [
            {
              targets = cfg.static-targets.dovecot;
            }
          ];
        }

        {
          job_name = "postfix";
          scheme = "https";
          metrics_path = "/metrics/postfix";
          honor_labels = false;
          dns_sd_configs = [
            {
              names = cfg.service-discovery-dns.postfix;
            }
          ];
          static_configs = [
            {
              targets = cfg.static-targets.postfix;
            }
          ];
        }

        {
          job_name = "rspamd";
          scheme = "https";
          metrics_path = "/metrics/rspamd";
          honor_labels = false;
          dns_sd_configs = [
            {
              names = cfg.service-discovery-dns.rspamd;
            }
          ];
          static_configs = [
            {
              targets = cfg.static-targets.rspamd;
            }
          ];
        }
      ];

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
