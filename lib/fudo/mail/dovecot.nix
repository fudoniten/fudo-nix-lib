{ config, lib, pkgs, environment, ... }:

with lib;
let
  cfg = config.fudo.mail-server;

  sieve-path = "${cfg.state-directory}/dovecot/imap_sieve";

  pipe-bin = pkgs.stdenv.mkDerivation {
    name = "pipe_bin";
    src = ./dovecot/pipe_bin;
    buildInputs = with pkgs; [ makeWrapper coreutils bash rspamd ];
    buildCommand = ''
      mkdir -p $out/pipe/bin
      cp $src/* $out/pipe/bin/
      chmod a+x $out/pipe/bin/*
      patchShebangs $out/pipe/bin

      for file in $out/pipe/bin/*; do
        wrapProgram $file \
          --set PATH "${pkgs.coreutils}/bin:${pkgs.rspamd}/bin"
      done
    '';
  };

  ldap-conf-template = ldap-cfg:
    let
      ssl-config = if (ldap-cfg.ca == null) then ''
        tls = no
        tls_require_cert = try
      '' else ''
        tls_ca_cert_file = ${ldap-cfg.ca}
        tls = yes
        tls_require_cert = try
      '';
    in
      pkgs.writeText "dovecot2-ldap-config.conf.template" ''
        uris = ${concatStringsSep " " ldap-cfg.server-urls}
        ldap_version = 3
        dn = ${ldap-cfg.reader-dn}
        dnpass = __LDAP_READER_PASSWORD__
        auth_bind = yes
        auth_bind_userdn = uid=%u,ou=members,dc=fudo,dc=org
        base = dc=fudo,dc=org
        ${ssl-config}
      '';

  ldap-conf-generator = ldap-cfg: let
    template = ldap-conf-template ldap-cfg;
    target-dir = dirOf ldap-cfg.generated-ldap-config;
    target = ldap-cfg.generated-ldap-config;
  in pkgs.writeScript "dovecot2-ldap-password-swapper.sh" ''
    mkdir -p ${target-dir}
    touch ${target}
    chmod 600 ${target}
    chown ${config.services.dovecot2.user} ${target}
    LDAP_READER_PASSWORD=$( cat "${ldap-cfg.reader-password-file}" )
    sed 's/__LDAP_READER_PASSWORD__/$LDAP_READER_PASSWORD/' '${template}' > ${target}
  '';

  ldap-passwd-entry = ldap-config: ''
    passdb {
      driver = ldap
      args = ${ldap-conf "ldap-passdb.conf" ldap-config}
    }
  '';

  ldapOpts = {
    options = with types; {
      ca = mkOption {
        type = nullOr str;
        description = "The path to the CA cert used to sign the LDAP server certificate.";
        default = null;
      };

      base = mkOption {
        type = str;
        description = "Base of the LDAP server database.";
        example = "dc=fudo,dc=org";
      };

      server-urls = mkOption {
        type = listOf str;
        description = "A list of LDAP server URLs used for authentication.";
      };

      reader-dn = mkOption {
        type = str;
        description = ''
          DN to use for reading user information. Needs access to homeDirectory,
          uidNumber, gidNumber, and uid, but not password attributes.
        '';
      };

      reader-password-file = mkOption {
        type = str;
        description = "Password for the user specified in ldap-reader-dn.";
      };

      generated-ldap-config = mkOption {
        type = str;
        description = "Path at which to store the generated LDAP config file, including password.";
        default = "/run/dovecot2/config/ldap.conf";
      };
    };
  };

  dovecot-user = config.services.dovecot2.user;

in {
  options.fudo.mail-server.dovecot = with types; {
    ssl-private-key = mkOption {
      type = str;
      description = "Location of the server SSL private key.";
    };

    ssl-certificate = mkOption {
      type = str;
      description = "Location of the server SSL certificate.";
    };

    ldap = mkOption {
      type = nullOr (submodule ldapOpts);
      default = null;
      description = ''
        LDAP auth server configuration. If omitted, the server will use local authentication.
      '';
    };
  };

  config = mkIf cfg.enable {

    services.prometheus.exporters.dovecot = mkIf cfg.monitoring {
      enable = true;
      scopes = ["user" "global"];
      listenAddress = "127.0.0.1";
      port = 9166;
      socketPath = "/var/run/dovecot2/old-stats";
    };

    services.dovecot2 = {
      enable = true;
      enableImap = true;
      enableLmtp = true;
      enablePop3 = true;
      enablePAM = cfg.dovecot.ldap == null;

      createMailUser = true;

      mailUser = cfg.mail-user;
      mailGroup = cfg.mail-group;
      mailLocation = "maildir:${cfg.mail-directory}/%u/";

      sslServerCert = cfg.dovecot.ssl-certificate;
      sslServerKey = cfg.dovecot.ssl-private-key;

      modules = [ pkgs.dovecot_pigeonhole ];
      protocols = [ "sieve" ];

      sieveScripts = {
        after = builtins.toFile "spam.sieve" ''
              require "fileinto";

              if header :is "X-Spam" "Yes" {
                fileinto "Junk";
                stop;
              }
            '';
      };

      mailboxes = cfg.mailboxes;

      extraConfig = ''
        #Extra Config

        ${optionalString cfg.monitoring ''
          # The prometheus exporter still expects an older style of metrics
          mail_plugins = $mail_plugins old_stats
          service old-stats {
            unix_listener old-stats {
              user = dovecot-exporter
              group = dovecot-exporter
            }
          }
        ''}

        ${lib.optionalString cfg.debug ''
          mail_debug = yes
          auth_debug = yes
          verbose_ssl = yes
        ''}

        protocol imap {
          mail_max_userip_connections = ${toString cfg.max-user-connections}
          mail_plugins = $mail_plugins imap_sieve
        }

        protocol pop3 {
          mail_max_userip_connections = ${toString cfg.max-user-connections}
        }

        protocol lmtp {
          mail_plugins = $mail_plugins sieve
        }

        mail_access_groups = ${cfg.mail-group}
        ssl = required

        # When looking up usernames, just use the name, not the full address
        auth_username_format = %n

        service lmtp {
          # Enable logging in debug mode
          ${optionalString cfg.debug "executable = lmtp -L"}

          # Unix socket for postfix to deliver messages via lmtp
          unix_listener dovecot-lmtp {
            user = "postfix"
            group = ${cfg.mail-group}
            mode = 0600
          }

          # Drop privs, since all mail is owned by one user
          # user = ${cfg.mail-user}
          # group = ${cfg.mail-group}
          user = root
        }

        auth_mechanisms = login plain

        ${optionalString (cfg.dovecot.ldap != null) ''
          passdb {
            driver = ldap
            args = ${cfg.dovecot.ldap.generated-ldap-config}
          }
        ''}
        userdb {
          driver = static
          args = uid=${toString cfg.mail-user-id} home=${cfg.mail-directory}/%u
        }

        # Used by postfix to authorize users
        service auth {
          unix_listener auth {
            mode = 0660
            user = "${config.services.postfix.user}"
            group = ${cfg.mail-group}
          }

          unix_listener auth-userdb {
            mode = 0660
            user = "${config.services.postfix.user}"
            group = ${cfg.mail-group}
          }
        }

        service auth-worker {
          user = root
        }

        service imap {
          vsz_limit = 1024M
        }

        namespace inbox {
          separator = "/"
          inbox = yes
        }

        plugin {
          sieve_plugins = sieve_imapsieve sieve_extprograms
          sieve = file:/var/sieve/%u/scripts;active=/var/sieve/%u/active.sieve
          sieve_default = file:/var/sieve/%u/default.sieve
          sieve_default_name = default
          # From elsewhere to Spam folder
          imapsieve_mailbox1_name = Junk
          imapsieve_mailbox1_causes = COPY
          imapsieve_mailbox1_before = file:${sieve-path}/report-spam.sieve
          # From Spam folder to elsewhere
          imapsieve_mailbox2_name = *
          imapsieve_mailbox2_from = Junk
          imapsieve_mailbox2_causes = COPY
          imapsieve_mailbox2_before = file:${sieve-path}/report-ham.sieve
          sieve_pipe_bin_dir = ${pipe-bin}/pipe/bin
          sieve_global_extensions = +vnd.dovecot.pipe +vnd.dovecot.environment
        }

        recipient_delimiter = +

        lmtp_save_to_detail_mailbox = yes

        lda_mailbox_autosubscribe = yes
        lda_mailbox_autocreate = yes
      '';
    };

    systemd = {
      tmpfiles.rules = [
        "d ${sieve-path} 750 ${dovecot-user} ${cfg.mail-group} - -"
      ];

      services.dovecot2.preStart = ''
        rm -f ${sieve-path}/*
        cp -p ${./dovecot/imap_sieve}/*.sieve ${sieve-path}
        for k in ${sieve-path}/*.sieve ; do
          ${pkgs.dovecot_pigeonhole}/bin/sievec "$k"
        done

        ${optionalString (cfg.dovecot.ldap != null)
          (ldap-conf-generator cfg.dovecot.ldap)}
      '';
    };
  };
}
