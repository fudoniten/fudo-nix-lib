{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.backplane;
  hostname = config.instance.hostname;

  host-secrets = config.fudo.secrets.host-secrets.${hostname};

  generate-auth-file = name: files: let
    make-entry = name: passwd-file:
      ''("${name}" . "${readFile passwd-file}")'';
    entries = mapAttrsToList make-entry files;
    content = concatStringsSep "\n" entries;
  in pkgs.writeText "${name}-backplane-auth.scm" "'(${content})";

  host-auth-file = generate-auth-file "host"
    (mapAttrs (hostname: hostOpts: hostOpts.password-file)
      cfg.client-hosts);

  service-auth-file = generate-auth-file "service"
    (mapAttrs (service: serviceOpts: serviceOpts.password-file)
      cfg.services);

  clientHostOpts = { name, ... }: {
    options = with types; {
      password-file = mkOption {
        type = path;
        description =
          "Location (on the build host) of the file containing the host password.";
      };
    };
  };

  serviceOpts = { name, ... }: {
    options = with types; {
      password-file = mkOption {
        type = path;
        description =
          "Location (on the build host) of the file containing the service password.";
      };
    };
  };

in {
  options.fudo.backplane = with types; {
    enable = mkEnableOption "Enable backplane XMPP server.";

    client-hosts = mkOption {
      type = attrsOf (submodule clientHostOpts);
      description = "List of backplane client options.";
      default = {};
    };

    services = mkOption {
      type = attrsOf (submodule serviceOpts);
      description = "List of backplane service options.";
      default = {};
    };

    backplane-hostname = mkOption {
      type = str;
      description = "Hostname of the backplane XMPP server.";
    };
  };

  config = mkIf cfg.enable {
    fudo = {
      secrets.host-secrets.${hostname} = {
        backplane-host-auth = {
          source-file = generate-auth-file "host"
            (mapAttrs (hostname: hostOpts: hostOpts.password-file)
              cfg.client-hosts);
          target-file = "/run/backplane/host-passwords.scm";
          user = config.fudo.jabber.user;
        };
        backplane-service-auth = {
          source-file = generate-auth-file "service"
            (mapAttrs (service: serviceOpts: serviceOpts.password-file)
              cfg.services);
          target-file = "/run/backplane/service-passwords.scm";
          user = config.fudo.jabber.user;
        };
      };

      jabber = {
        environment = {
          FUDO_HOST_PASSWD_FILE =
            host-secrets.backplane-host-auth.target-file;
          FUDO_SERVICE_PASSWD_FILE =
            host-secrets.backplane-service-auth.target-file;
        };

        sites.${cfg.backplane-hostname} = {
          hostname = cfg.backplane-hostname;

          site-config = {
            auth_method = "external";
            extauth_program =
              "${pkgs.guile}/bin/guile -s ${pkgs.backplane-auth}/backplane-auth.scm";
            extauth_pool_size = 3;
            auth_use_cache = true;

            modules = {
              mod_adhoc = {};
              mod_caps = {};
              mod_carboncopy = {};
              mod_client_state = {};
              mod_configure = {};
              mod_disco = {};
              mod_fail2ban = {};
              mod_last = {};
              mod_offline.access_max_user_messages = 5000;
              mod_ping = {};
              mod_pubsub = {
                access_createnode = "pubsub_createnode";
                ignore_pep_from_offline = true;
                last_item_cache = false;
                plugins = [
                  "flat"
                  "pep"
                ];
              };
              mod_roster = {};
              mod_stream_mgmt = {};
              mod_time = {};
              mod_version = {};
            };
          };
        };
      };
    };
  };
}
