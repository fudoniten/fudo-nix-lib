{ config, lib, pkgs, ... }:

with lib;
{
  config = mkIf config.fudo.jabber.enable {
    fudo = let
      cfg = config.fudo.backplane;

      hostname = config.instance.hostname;

      backplane-server = cfg.backplane-host;

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

    in {
      secrets.host-secrets.${hostname} = {
        backplane-host-auth = {
          source-file = host-auth-file;
          target-file = "/var/backplane/host-passwords.scm";
          user = config.fudo.jabber.user;
        };
        backplane-service-auth = {
          source-file = service-auth-file;
          target-file = "/var/backplane/service-passwords.scm";
          user = config.fudo.jabber.user;
        };
      };

      jabber = {
        environment = {
          FUDO_HOST_PASSWD_FILE =
            secrets.backplane-host-auth.target-file;
          FUDO_SERVICE_PASSWD_FILE =
            secrets.backplane-service-auth.target-file;
        };

        sites.${backplane-server} = {
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
              mod_offline = {
                access_max_user_messages = 5000;
              };
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
