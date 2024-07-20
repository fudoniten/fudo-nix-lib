# NOTE: this assumes that postgres is running locally.

{ config, lib, pkgs, ... }@toplevel:

with lib;
let
  cfg = config.fudo.metrics.grafana;

  hostname = config.instance.hostname;
  domain-name = config.fudo.hosts.${hostname}.domain;

  host-secrets = config.fudo.secrets.host-secrets.${hostname};

  datasourceOpts = { name, ... }: {
    options = with types; {
      url = mkOption {
        type = str;
        description = "Datasource URL.";
      };

      type = mkOption {
        type = enum [ "prometheus" "loki" ];
        description = "Type of the datasource.";
      };

      name = mkOption {
        type = str;
        description = "Name of the datasource.";
        default = name;
      };

      default = mkOption {
        type = bool;
        description = "Use this datasource as the default while querying.";
        default = false;
      };
    };
  };

  ldapOpts = {
    options = with types; {
      hosts = mkOption {
        type = listOf str;
        description = "LDAP server hostnames.";
      };

      bind-dn = mkOption {
        type = str;
        description = "DN as which to bind with the LDAP server.";
      };

      bind-passwd = mkOption {
        type = str;
        description = "Password with which to bind to the LDAP server.";
      };

      base-dn = mkOption {
        type = str;
        description = "DN under which to search for users.";
      };
    };
  };

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
        description =
          "Address from which mail will be sent (i.e. 'from' address).";
        default =
          "${toplevel.config.fudo.grafana.smtp.username}@${domain-name}";
      };

      domain = mkOption {
        type = str;
        description = "Domain of the SMTP server.";
        default = toplevel.config.instance.local-domain;
      };
    };

    oauth = let
      oauthOpts.options = {
        hostname = mkOption {
          type = str;
          description = "Host of the OAuth server.";
        };

        client-id = mkOption {
          type = str;
          description = "Path to file containing the Grafana OAuth client ID.";
        };

        client-secret = mkOption {
          type = str;
          description =
            "Path to file containing the Grafana OAuth client secret.";
        };

        slug = mkOption {
          type = str;
          description = "The application slug on the OAuth server.";
        };
      };
    in mkOption {
      type = nullOr (submodule oauthOpts);
      default = null;
    };

    # ldap = mkOption {
    #   type = nullOr (submodule ldapOpts);
    #   description = "";
    #   default = null;
    # };

    admin-password-file = mkOption {
      type = str;
      description = "Path to a file containing the admin user's password.";
    };

    secret-key-file = mkOption {
      type = str;
      description =
        "Path to a file containing the server's secret key, used for signatures.";
    };

    datasources = mkOption {
      type = attrsOf (submodule datasourceOpts);
      description = "A list of datasources supplied to Grafana.";
      default = { };
    };

    state-directory = mkOption {
      type = str;
      description = "Directory at which to store Grafana state data.";
    };

    private-network = mkEnableOption "Network is private, no SSL.";
  };

  config = mkIf cfg.enable {
    systemd = {
      tmpfiles.rules =
        let grafana-user = config.systemd.services.grafana.serviceConfig.User;
        in [ "d ${cfg.state-directory} 0700 ${grafana-user} - - -" ];
    };

    # fudo.secrets.host-secrets.${hostname}.grafana-environment-file = {
    #   source-file = pkgs.writeText "grafana.env" ''
    #     ${optionalString (cfg.ldap != null)
    #     ''GRAFANA_LDAP_BIND_PASSWD="${cfg.ldap.bind-passwd}"''}
    #   '';
    #   target-file = "/run/metrics/grafana/auth-bind.passwd";
    #   user = config.systemd.services.grafana.serviceConfig.User;
    # };

    services = {
      nginx = {
        enable = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;

        virtualHosts = {
          "${cfg.hostname}" = {
            enableACME = !cfg.private-network;
            forceSSL = !cfg.private-network;
            locations."/".proxyPass = "http://127.0.0.1:3000";
          };
        };
      };

      grafana = {
        enable = true;

        dataDir = cfg.state-directory;

        settings = {

          server = {
            root_url =
              let scheme = if cfg.private-network then "http" else "https";
              in "${scheme}://${cfg.hostname}/";
            http_addr = "127.0.0.1";
            http_port = 3000;
            protocol = "http";
            domain = cfg.hostname;
          };

          smtp = {
            enable = true;
            # TODO: create system user as necessary
            from_address = "${cfg.smtp.username}@${cfg.smtp.domain}";
            host = "${cfg.smtp.hostname}:25";
            user = cfg.smtp.username;
            password = "$__file{${cfg.smtp.password-file}}";
          };

          security = {
            admin_password = "$__file{${cfg.admin-password-file}}";
            secret_key = "$__file{${cfg.secret-key-file}}";
          };

          database = {
            type = "sqlite3";
            path = "${cfg.state-directory}/database.sqlite";
          };

          auth = mkIf (!isNull cfg.oauth) {
            signout_redirect_url =
              "https://${cfg.oauth.hostname}/application/o/${cfg.oauth.slug}/end-session/";
            oauth_auto_login = true;
          };

          "auth.generic_oauth" = mkIf (!isNull cfg.oauth) {
            name = "Authentik";
            enabled = true;
            client_id = "$__file{${cfg.oauth.client-id}}";
            client_secret = "$__file{${cfg.oauth.client-secret}}";
            scopes = "openid email profile";
            auth_url = "https://${cfg.oauth.hostname}/application/o/authorize/";
            token_url = "https://${cfg.oauth.hostname}/application/o/token/";
            api_url = "https://${cfg.oauth.hostname}/application/o/userinfo/";
            role_attribute_path = concatStringsSep " || " [
              "contains(groups[*], 'Metrics Admin') && 'Admin'"
              "contains(groups[*], 'Metrics Editor') && 'Editor'"
              "'Viewer'"
            ];
          };
        };

        provision = {
          enable = true;
          datasources.settings.datasources = let
            make-datasource = datasource: {
              editable = false;
              isDefault = datasource.default;
              inherit (datasource) name type url;
            };
          in map make-datasource (attrValues cfg.datasources);
        };
      };
    };
  };
}
