# NOTE: this assumes that postgres is running locally.

{ config, lib, pkgs, ... } @ toplevel:

with lib;
let
  cfg = config.fudo.grafana;

  hostname = config.instance.hostname;
  domain-name = config.fudo.hosts.${hostname}.domain;

in {

  options.fudo.grafana = {
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
  };

  config = mkIf cfg.enable {
    services.nginx = {
      enable = true;

      virtualHosts = {
        "${cfg.hostname}" = {
          enableACME = true;
          forceSSL = true;

          locations."/" = {
            proxyPass = "http://127.0.0.1:3000";

            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-By $server_addr:$server_port;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
          };
        };
      };
    };

    services.grafana = {
      enable = true;

      addr = "127.0.0.1";
      protocol = "http";
      port = 3000;
      domain = cfg.hostname;
      rootUrl = "https://${cfg.hostname}/";
      dataDir = cfg.state-directory;

      security = {
        adminPasswordFile = cfg.admin-password-file;
        secretKeyFile = cfg.secret-key-file;
      };

      smtp = {
        enable = true;
        fromAddress = "metrics@fudo.org";
        host = "mail.fudo.org:25";
        user = cfg.smtp-username;
        passwordFile = cfg.smtp-password-file;
      };

      database = {
        host = cfg.database.hostname;
        name = cfg.database.name;
        user = cfg.database.user;
        passwordFile = cfg.database.password-file;
        type = "postgres";
      };

      provision.datasources = [
        {
          editable = false;
          isDefault = true;
          name = cfg.prometheus-host;
          type = "prometheus";
          url = "https://${cfg.prometheus-host}/";
        }
      ];
    };
  };
}
