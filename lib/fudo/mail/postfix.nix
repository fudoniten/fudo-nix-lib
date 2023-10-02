{ config, pkgs, lib, ... }:

with lib;
let
  inherit (lib.strings) concatStringsSep;

  cfg = config.fudo.mail-server;

  # The final newline is important
  write-entries = filename: entries:
    let entries-string = (concatStringsSep "\n" entries);
    in builtins.toFile filename ''
      ${entries-string}
    '';

  make-user-aliases = entries:
    concatStringsSep "\n" (mapAttrsToList (user: aliases:
      concatStringsSep "\n" (map (alias: "${alias}  ${user}") aliases))
      entries);

  make-alias-users = domains: entries:
    concatStringsSep "\n" (flatten (mapAttrsToList (alias: users:
      (map (domain: "${alias}@${domain}  ${concatStringsSep "," users}")
        domains)) entries));

  policyd-spf = pkgs.writeText "policyd-spf.conf"
    (cfg.postfix.policy-spf-extra-config + (lib.optionalString cfg.debug ''
      debugLevel = 4
    ''));

  submission-header-cleanup-rules =
    pkgs.writeText "submission_header_cleanup_rules" (''
      # Removes sensitive headers from mails handed in via the submission port.
      # See https://thomas-leister.de/mailserver-debian-stretch/
      # Uses "pcre" style regex.

      /^Received:/            IGNORE
      /^X-Originating-IP:/    IGNORE
      /^X-Mailer:/            IGNORE
      /^User-Agent:/          IGNORE
      /^X-Enigmail:/          IGNORE
    '');
  blacklist-postfix-entry = sender: "${sender} REJECT";
  blacklist-postfix-file = filename: entries: write-entries filename entries;
  sender-blacklist-file = blacklist-postfix-file "reject_senders"
    (map blacklist-postfix-entry cfg.sender-blacklist);
  recipient-blacklist-file = blacklist-postfix-file "reject_recipients"
    (map blacklist-postfix-entry cfg.recipient-blacklist);

  # A list of domains for which we accept mail
  virtual-mailbox-map-file = write-entries "virtual_mailbox_map"
    (map (domain: "@${domain}  OK") (cfg.local-domains ++ [ cfg.domain ]));

  sender-login-map-file =
    let escapeDot = (str: replaceStrings [ "." ] [ "\\." ] str);
    in write-entries "sender_login_maps"
    (map (domain: "/^(.*)@${escapeDot domain}$/   \${1}")
      (cfg.local-domains ++ [ cfg.domain ]));

  mapped-file = name: "hash:/var/lib/postfix/conf/${name}";

  pcre-file = name: "pcre:/var/lib/postfix/conf/${name}";

in {

  options.fudo.mail-server.postfix = {

    ssl-private-key = mkOption {
      type = types.str;
      description = "Location of the server SSL private key.";
    };

    ssl-certificate = mkOption {
      type = types.str;
      description = "Location of the server SSL certificate.";
    };

    policy-spf-extra-config = mkOption {
      type = types.lines;
      default = "";
      example = ''
        skip_addresses = 127.0.0.0/8,::ffff:127.0.0.0/104,::1
      '';
      description = ''
        Extra configuration options for policyd-spf. This can be use to among
        other things skip spf checking for some IP addresses.
      '';
    };
  };

  config = mkIf cfg.enable {

    services.prometheus.exporters.postfix = mkIf cfg.monitoring.enable {
      enable = true;
      systemd.enable = true;
      showqPath = "/var/lib/postfix/queue/public/showq";
      user = config.services.postfix.user;
      group = config.services.postfix.group;
      port = cfg.monitoring.postfix-listen-port;
      listenAddress = "127.0.0.1";
    };

    services.postfix = {
      enable = true;
      domain = cfg.domain;
      origin = cfg.domain;
      hostname = cfg.mail-hostname;
      destination = [ "localhost" "localhost.localdomain" ];
      # destination = ["localhost" "localhost.localdomain" cfg.hostname] ++
      #               cfg.local-domains;;

      enableHeaderChecks = true;
      enableSmtp = true;
      enableSubmission = true;

      mapFiles."reject_senders" = sender-blacklist-file;
      mapFiles."reject_recipients" = recipient-blacklist-file;
      mapFiles."virtual_mailbox_map" = virtual-mailbox-map-file;
      mapFiles."sender_login_map" = sender-login-map-file;

      # TODO: enable!
      # headerChecks = [ { action = "REDIRECT spam@example.com"; pattern = "/^X-Spam-Flag:/"; } ];
      networks = cfg.trusted-networks;

      virtual = ''
        ${make-user-aliases cfg.user-aliases}

        ${make-alias-users ([ cfg.domain ] ++ cfg.local-domains)
        cfg.alias-users}
      '';

      sslCert = cfg.postfix.ssl-certificate;
      sslKey = cfg.postfix.ssl-private-key;

      config = {
        virtual_mailbox_domains = cfg.local-domains ++ [ cfg.domain ];
        # virtual_mailbox_base = "${cfg.mail-directory}/";
        virtual_mailbox_maps = mapped-file "virtual_mailbox_map";

        virtual_uid_maps = "static:${toString cfg.mail-user-id}";
        virtual_gid_maps =
          "static:${toString config.users.groups."${cfg.mail-group}".gid}";

        virtual_transport = "lmtp:unix:/run/dovecot2/dovecot-lmtp";

        # NOTE: it's important that this ends with /, to indicate Maildir format!
        # mail_spool_directory = "${cfg.mail-directory}/";
        message_size_limit = toString (cfg.message-size-limit * 1024 * 1024);

        smtpd_banner = "${cfg.mail-hostname} ESMTP NO UCE";

        tls_eecdh_strong_curve = "prime256v1";
        tls_eecdh_ultra_curve = "secp384r1";

        policy-spf_time_limit = "3600s";

        smtp_host_lookup = "dns, native";

        smtpd_sasl_type = "dovecot";
        smtpd_sasl_path = "/run/dovecot2/auth";
        smtpd_sasl_auth_enable = "yes";
        smtpd_sasl_local_domain = "fudo.org";

        smtpd_sasl_security_options = "noanonymous";
        smtpd_sasl_tls_security_options = "noanonymous";

        smtpd_sender_login_maps = (pcre-file "sender_login_map");

        disable_vrfy_command = "yes";

        recipient_delimiter = "+";

        milter_protocol = "6";
        milter_mail_macros =
          "i {mail_addr} {client_addr} {client_name} {auth_type} {auth_authen} {auth_author} {mail_addr} {mail_host} {mail_mailer}";

        smtpd_milters = [
          "unix:/run/rspamd/rspamd-milter.sock"
          "unix:/var/run/opendkim/opendkim.sock"
        ];

        non_smtpd_milters = [
          "unix:/run/rspamd/rspamd-milter.sock"
          "unix:/var/run/opendkim/opendkim.sock"
        ];

        smtpd_relay_restrictions = [
          "permit_mynetworks"
          "permit_sasl_authenticated"
          "reject_unauth_destination"
          "reject_unauth_pipelining"
          "reject_unauth_destination"
          "reject_unknown_sender_domain"
        ];

        smtpd_sender_restrictions = [
          "check_sender_access ${mapped-file "reject_senders"}"
          "permit_mynetworks"
          "permit_sasl_authenticated"
          "reject_unknown_sender_domain"
        ];

        smtpd_recipient_restrictions = [
          "check_sender_access ${mapped-file "reject_recipients"}"
          "permit_mynetworks"
          "permit_sasl_authenticated"
          "check_policy_service unix:private/policy-spf"
          "reject_unknown_recipient_domain"
          "reject_unauth_pipelining"
          "reject_unauth_destination"
          "reject_invalid_hostname"
          "reject_non_fqdn_hostname"
          "reject_non_fqdn_sender"
          "reject_non_fqdn_recipient"
        ];

        smtpd_helo_restrictions =
          [ "permit_mynetworks" "reject_invalid_hostname" "permit" ];

        # Handled by submission
        smtpd_tls_security_level = "may";

        smtpd_tls_eecdh_grade = "ultra";

        # Disable obselete protocols
        smtpd_tls_protocols =
          [ "TLSv1.2" "TLSv1.1" "!TLSv1" "!SSLv2" "!SSLv3" ];
        smtp_tls_protocols = [ "TLSv1.2" "TLSv1.1" "!TLSv1" "!SSLv2" "!SSLv3" ];
        smtpd_tls_mandatory_protocols =
          [ "TLSv1.2" "TLSv1.1" "!TLSv1" "!SSLv2" "!SSLv3" ];
        smtp_tls_mandatory_protocols =
          [ "TLSv1.2" "TLSv1.1" "!TLSv1" "!SSLv2" "!SSLv3" ];

        smtp_tls_ciphers = "high";
        smtpd_tls_ciphers = "high";
        smtp_tls_mandatory_ciphers = "high";
        smtpd_tls_mandatory_ciphers = "high";

        smtpd_tls_mandatory_exclude_ciphers =
          [ "MD5" "DES" "ADH" "RC4" "PSD" "SRP" "3DES" "eNULL" "aNULL" ];
        smtpd_tls_exclude_ciphers =
          [ "MD5" "DES" "ADH" "RC4" "PSD" "SRP" "3DES" "eNULL" "aNULL" ];
        smtp_tls_mandatory_exclude_ciphers =
          [ "MD5" "DES" "ADH" "RC4" "PSD" "SRP" "3DES" "eNULL" "aNULL" ];
        smtp_tls_exclude_ciphers =
          [ "MD5" "DES" "ADH" "RC4" "PSD" "SRP" "3DES" "eNULL" "aNULL" ];

        tls_preempt_cipherlist = "yes";

        smtpd_tls_auth_only = "yes";

        smtpd_tls_loglevel = "1";

        tls_random_source = "dev:/dev/urandom";
      };

      submissionOptions = {
        smtpd_tls_security_level = "encrypt";
        smtpd_sasl_auth_enable = "yes";
        smtpd_sasl_type = "dovecot";
        smtpd_sasl_path = "/run/dovecot2/auth";
        smtpd_sasl_security_options = "noanonymous";
        smtpd_sasl_local_domain = cfg.domain;
        smtpd_client_restrictions = "permit_sasl_authenticated,reject";
        smtpd_sender_restrictions =
          "reject_sender_login_mismatch,reject_unknown_sender_domain";
        smtpd_recipient_restrictions =
          "reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject";
        cleanup_service_name = "submission-header-cleanup";
      };

      masterConfig = {
        "policy-spf" = {
          type = "unix";
          privileged = true;
          chroot = false;
          command = "spawn";
          args = [
            "user=nobody"
            "argv=${pkgs.pypolicyd-spf}/bin/policyd-spf"
            "${policyd-spf}"
          ];
        };
        "submission-header-cleanup" = {
          type = "unix";
          private = false;
          chroot = false;
          maxproc = 0;
          command = "cleanup";
          args =
            [ "-o" "header_checks=pcre:${submission-header-cleanup-rules}" ];
        };
      };
    };

    # Postfix requires dovecot lmtp socket, dovecot auth socket and certificate to work
    systemd.services.postfix = {
      after = [ "dovecot2.service" ]
        ++ (lib.optional cfg.dkim.signing "opendkim.service");
      requires = [ "dovecot2.service" ]
        ++ (lib.optional cfg.dkim.signing "opendkim.service");
    };
  };
}
