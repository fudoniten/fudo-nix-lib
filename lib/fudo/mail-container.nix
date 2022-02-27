{ pkgs, lib, config, ... }:
with lib;
let
  hostname = config.instance.hostname;
  cfg = config.fudo.mail-server;
  container-maildir = "/var/lib/mail";
  container-statedir = "/var/lib/mail-state";

  # Don't bother with group-id, nixos doesn't seem to use it anyway
  container-mail-user = "mailer";
  container-mail-user-id = 542;
  container-mail-group = "mailer";

  build-timestamp = config.instance.build-timestamp;
  build-seed = config.instance.build-seed;
  site = config.instance.local-site;
  domain = cfg.domain;

  local-networks = config.instance.local-networks;

in rec {
  config = mkIf (cfg.enableContainer) {
    # Disable postfix on this host--it'll be run in the container instead
    services.postfix.enable = false;

    services.nginx = mkIf cfg.monitoring.enable {
      enable = true;

      virtualHosts = let
        proxy-headers = ''
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header Host $host;
        '';
        trusted-network-string =
          optionalString ((length local-networks) > 0)
          (concatStringsSep "\n"
            (map (network: "allow ${network};")
              local-networks)) + ''

              deny all;'';

      in {
        "${cfg.mail-hostname}" = {
          enableACME = true;
          forceSSL = true;

          locations."/metrics/postfix" = {
            proxyPass = "http://127.0.0.1:${cfg.monitoring.postfix-listen-port}/metrics";

            extraConfig = ''
              ${proxy-headers}

              ${trusted-network-string}
            '';
          };

          locations."/metrics/dovecot" = {
            proxyPass = "http://127.0.0.1:${cfg.monitoring.dovecot-listen-port}/metrics";

            extraConfig = ''
              ${proxy-headers}

              ${trusted-network-string}
            '';
          };

          locations."/metrics/rspamd" = {
            proxyPass = "http://127.0.0.1:${cfg.monitoring.rspamd-listen-port}/metrics";

            extraConfig = ''
              ${proxy-headers}

              ${trusted-network-string}
            '';
          };
        };
      };
    };

    containers.mail-server = {

      autoStart = true;

      bindMounts = {
        "${container-maildir}" = {
          hostPath = cfg.mail-directory;
          isReadOnly = false;
        };

        "${container-statedir}" = {
          hostPath = cfg.state-directory;
          isReadOnly = false;
        };

        "/run/mail/certs/postfix/cert.pem" = {
          hostPath = cfg.ssl.certificate;
          isReadOnly = true;
        };

        "/run/mail/certs/postfix/key.pem" = {
          hostPath = cfg.ssl.private-key;
          isReadOnly = true;
        };

        "/run/mail/certs/dovecot/cert.pem" = {
          hostPath = cfg.ssl.certificate;
          isReadOnly = true;
        };

        "/run/mail/certs/dovecot/key.pem" = {
          hostPath = cfg.ssl.private-key;
          isReadOnly = true;
        };

        "/run/mail/passwords/dovecot/ldap-reader.passwd" = {
          hostPath = cfg.dovecot.ldap.reader-password-file;
          isReadOnly = true;
        };
      };

      config = { config, pkgs, ... }: {

        imports = let
          initialize-host = import ../../initialize.nix;
          profile = "container";
        in [
          ./mail.nix

          (initialize-host {
            inherit
              lib
              pkgs
              build-timestamp
              site
              domain
              profile;
            hostname = "mail-container";
          })
        ];

        instance.build-seed = build-seed;

        environment.etc = {
          "mail-server/postfix/cert.pem" = {
            source = "/run/mail/certs/postfix/cert.pem";
            user = config.services.postfix.user;
            mode = "0444";
          };
          "mail-server/postfix/key.pem" = {
            source = "/run/mail/certs/postfix/key.pem";
            user = config.services.postfix.user;
            mode = "0400";
          };
          "mail-server/dovecot/cert.pem" = {
            source = "/run/mail/certs/dovecot/cert.pem";
            user = config.services.dovecot2.user;
            mode = "0444";
          };
          "mail-server/dovecot/key.pem" = {
            source = "/run/mail/certs/dovecot/key.pem";
            user = config.services.dovecot2.user;
            mode = "0400";
          };

          ## The pre-script runs as root anyway...
          # "mail-server/dovecot/ldap-reader.passwd" = {
          #   source = "/run/mail/passwords/dovecot/ldap-reader.passwd";
          #   user = config.services.dovecot2.user;
          #   mode = "0400";
          # };
        };

        fudo = {

          mail-server = {
            enable = true;
            mail-hostname = cfg.mail-hostname;
            domain = cfg.domain;

            debug = cfg.debug;
            monitoring = cfg.monitoring.enable;

            state-directory = container-statedir;
            mail-directory = container-maildir;

            postfix = {
              ssl-certificate = "/etc/mail-server/postfix/cert.pem";
              ssl-private-key = "/etc/mail-server/postfix/key.pem";
            };

            dovecot = {
              ssl-certificate = "/etc/mail-server/dovecot/cert.pem";
              ssl-private-key = "/etc/mail-server/dovecot/key.pem";
              ldap = {
                server-urls = cfg.dovecot.ldap.server-urls;
                reader-dn = cfg.dovecot.ldap.reader-dn;
                reader-password-file = "/run/mail/passwords/dovecot/ldap-reader.passwd";
              };
            };

            local-domains = cfg.local-domains;

            alias-users = cfg.alias-users;
            user-aliases = cfg.user-aliases;
            sender-blacklist = cfg.sender-blacklist;
            recipient-blacklist = cfg.recipient-blacklist;
            trusted-networks = cfg.trusted-networks;

            mail-user = container-mail-user;
            mail-user-id = container-mail-user-id;
            mail-group = container-mail-group;

            clamav.enable = cfg.clamav.enable;

            dkim.signing = cfg.dkim.signing;
          };
        };
      };
    };
  };
}
