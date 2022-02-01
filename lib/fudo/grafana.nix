# NOTE: this assumes that postgres is running locally.

{ config, lib, pkgs, ... } @ toplevel:

with lib;
let
  cfg = config.fudo.metrics.grafana;

  hostname = config.instance.hostname;
  domain-name = config.fudo.hosts.${hostname}.domain;

in {

  options.fudo.metrics.grafana = with types; {
    enable = mkEnableOption "Fudo Metrics Display Service";

    hostname = mkOption {
      type = str;
      description = "Grafana site hostname.";
      example = "fancy-graphs.fudo.org";
    };

    smtp = {
      username = mkOption {
        type = str;
        description = "Username with which to send email.";
        default = "metrics";
      };

      password-file = mkOption {
        type = str;
        description = "Path to a file containing the email user's password.";
      };

      hostname = mkOption {
        type = str;
        description = "Mail server hostname.";
        default = "mail.${domain-name}";
      };

      email = mkOption {
        type = str;
        description = "Address from which mail will be sent (i.e. 'from' address).";
        default = "${toplevel.config.fudo.grafana.smtp.username}@${domain-name}";
      };
    };

    database = {
      name = mkOption {
        type = str;
        description = "Database name.";
        default = "grafana";
      };
      hostname = mkOption {
        type = str;
        description = "Hostname of the database server.";
        default = "localhost";
      };
      user = mkOption {
        type = str;
        description = "Database username.";
        default = "grafana";
      };
      password-file = mkOption {
        type = str;
        description = "File containing the database user's password.";
      };
    };

    admin-password-file = mkOption {
      type = str;
      description = "Path to a file containing the admin user's password.";
    };

    secret-key-file = mkOption {
      type = str;
      description = "Path to a file containing the server's secret key, used for signatures.";
    };

    prometheus-hosts = mkOption {
      type = listOf str;
      description = "A list of URLs to prometheus data sources.";
      default = [];
    };

    state-directory = mkOption {
      type = str;
      description = "Directory at which to store Grafana state data.";
      default = "/var/lib/grafana";
    };

    private-network = mkEnableOption "Network is private, no SSL.";
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = let
      grafana-user = config.systemd.services.grafana.serviceConfig.User;
    in [
      "d ${cfg.state-directory} 0700 ${grafana-user} - - -"
    ];

    services = {
      nginx = {
        enable = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;

        virtualHosts = {
          "${cfg.hostname}" = {
            enableACME = ! cfg.private-network;
            forceSSL = ! cfg.private-network;
            locations."/".proxyPass = "http://127.0.0.1:3000";
          };
        };
      };

      grafana = {
        enable = true;

        addr = "127.0.0.1";
        protocol = "http";
        port = 3000;
        domain = cfg.hostname;
        rootUrl = let
          scheme = if cfg.private-network then "http" else "https";
        in "${scheme}://${cfg.hostname}/";
        dataDir = cfg.state-directory;

        security = {
          adminPasswordFile = cfg.admin-password-file;
          secretKeyFile = cfg.secret-key-file;
        };

        smtp = {
          enable = true;
          fromAddress = "metrics@fudo.org";
          host = "${cfg.smtp.hostname}:25";
          user = cfg.smtp.username;
          passwordFile = cfg.smtp.password-file;
        };

        database = {
          host = cfg.database.hostname;
          name = cfg.database.name;
          user = cfg.database.user;
          passwordFile = cfg.database.password-file;
          type = "postgres";
        };

        provision.datasources = imap0 (i: host: {
          editable = false;
          isDefault = (i == 0);
          name = builtins.trace "PROMETHEUS-HOST: ${host}" host;
          type = "prometheus";
          url = let
            scheme = if private-network then "http" else "https";
          in "${scheme}://${host}/";
        }) cfg.prometheus-hosts;
      };
    };
  };
}
