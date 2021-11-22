# NOTE: this assumes that postgres is running locally.

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.grafana;
  fudo-cfg = config.fudo.common;

  database-name = "grafana";
  database-user = "grafana";

  databaseOpts = { ... }: {
    options = {
      name = mkOption {
        type = types.str;
        description = "Database name.";
      };
      hostname = mkOption {
        type = types.str;
        description = "Hostname of the database server.";
      };
      user = mkOption {
        type = types.str;
        description = "Database username.";
      };
      password-file = mkOption {
        type = types.path;
        description = "File containing the database user's password.";
      };
    };
  };

in {

  options.fudo.grafana = {
    enable = mkEnableOption "Fudo Metrics Display Service";

    hostname = mkOption {
      type = types.str;
      description = "Grafana site hostname.";
      example = "fancy-graphs.fudo.org";
    };

    smtp-username = mkOption {
      type = types.str;
      description = "Username with which to send email.";
    };

    smtp-password-file = mkOption {
      type = types.path;
      description = "Path to a file containing the email user's password.";
    };

    database = mkOption {
      type = (types.submodule databaseOpts);
      description = "Grafana database configuration.";
    };

    admin-password-file = mkOption {
      type = types.path;
      description = "Path to a file containing the admin user's password.";
    };

    secret-key-file = mkOption {
      type = types.path;
      description = "Path to a file containing the server's secret key, used for signatures.";
    };

    prometheus-host = mkOption {
      type = types.str;
      description = "The URL of the prometheus data source.";
    };
  };

  config = mkIf cfg.enable {
    security.acme.certs.${cfg.hostname}.email = fudo-cfg.admin-email;

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
      domain = "${cfg.hostname}";
      rootUrl = "https://${cfg.hostname}/";

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
