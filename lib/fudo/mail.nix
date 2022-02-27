{ config, lib, pkgs, environment, ... }:

with lib;
let
  inherit (lib.strings) concatStringsSep;
  cfg = config.fudo.mail-server;

in {

  options.fudo.mail-server = with types; {
    enable = mkEnableOption "Fudo Email Server";

    enableContainer = mkEnableOption ''
      Run the mail server in a container.

      Mutually exclusive with mail-server.enable.
    '';

    domain = mkOption {
      type = str;
      description = "The main and default domain name for this email server.";
    };

    mail-hostname = mkOption {
      type = str;
      description = "The domain name to use for the mail server.";
    };

    ldap-url = mkOption {
      type = str;
      description = "URL of the LDAP server to use for authentication.";
      example = "ldaps://auth.fudo.org/";
    };

    monitoring = {
      enable = mkEnableOption "Enable monitoring for the mail server.";

      dovecot-listen-port = mkOption {
        type = port;
        description = "Port on which to serve Postfix metrics.";
        default = 9166;
      };

      postfix-listen-port = mkOption {
        type = port;
        description = "Port on which to serve Postfix metrics.";
        default = 9154;
      };

      rspamd-listen-port = mkOption {
        type = port;
        description = "Port on which to serve Postfix metrics.";
        default = 7980;
      };
    };

    mail-user = mkOption {
      type = str;
      description = "User to use for mail delivery.";
      default = "mailuser";
    };

    # No group id, because NixOS doesn't seem to use it
    mail-group = mkOption {
      type = str;
      description = "Group to use for mail delivery.";
      default = "mailgroup";
    };

    mail-user-id = mkOption {
      type = int;
      description = "UID of mail-user.";
      default = 525;
    };

    local-domains = mkOption {
      type = listOf str;
      description = "A list of domains for which we accept mail.";
      default = ["localhost" "localhost.localdomain"];
      example = [
        "localhost"
        "localhost.localdomain"
        "somedomain.com"
        "otherdomain.org"
      ];
    };

    mail-directory = mkOption {
      type = str;
      description = "Path to use for mail storage.";
    };

    state-directory = mkOption {
      type = str;
      description = "Path to use for state data.";
    };

    trusted-networks = mkOption {
      type = listOf str;
      description = "A list of trusted networks, for which we will happily relay without auth.";
      example = [
        "10.0.0.0/16"
        "192.168.0.0/24"
      ];
    };

    sender-blacklist = mkOption {
      type = listOf str;
      description = "A list of email addresses for whom we will not send email.";
      default = [];
      example = [
        "baduser@test.com"
        "change-pw@test.com"
      ];
    };

    recipient-blacklist = mkOption {
      type = listOf str;
      description = "A list of email addresses for whom we will not accept email.";
      default = [];
      example = [
        "baduser@test.com"
        "change-pw@test.com"
      ];
    };

    message-size-limit = mkOption {
      type = int;
      description = "Size of max email in megabytes.";
      default = 30;
    };

    user-aliases = mkOption {
      type = attrsOf (listOf str);
      description = "A map of real user to list of alias emails.";
      default = {};
      example = {
        someuser = ["alias0" "alias1"];
      };
    };

    alias-users = mkOption {
      type = attrsOf (listOf str);
      description = "A map of email alias to a list of users.";
      example = {
        alias = ["realuser0" "realuser1"];
      };
    };

    mailboxes = mkOption {
      description = ''
        The mailboxes for dovecot.

        Depending on the mail client used it might be necessary to change some mailbox's name.
     '';
      default = {
        Trash = {
          auto = "create";
          specialUse = "Trash";
          autoexpunge = "30d";
        };
        Junk = {
          auto = "create";
          specialUse = "Junk";
          autoexpunge = "60d";
        };
        Drafts = {
          auto = "create";
          specialUse = "Drafts";
          autoexpunge = "60d";
        };
        Sent = {
          auto = "subscribe";
          specialUse = "Sent";
        };
        Archive = {
          auto = "no";
          specialUse = "Archive";
        };
        Flagged = {
          auto = "no";
          specialUse = "Flagged";
        };
      };
    };

    debug = mkOption {
      description = "Enable debugging on mailservers.";
      type = bool;
      default = false;
    };

    max-user-connections = mkOption {
      description = "Max simultaneous connections per user.";
      type = int;
      default = 20;
    };

    ssl = {
      certificate = mkOption {
        type = str;
        description = "Path to the ssl certificate for the mail server to use.";
      };

      private-key = mkOption {
        type = str;
        description = "Path to the ssl private key for the mail server to use.";
      };
    };
  };

  imports = [
    ./mail/dkim.nix
    ./mail/dovecot.nix
    ./mail/postfix.nix
    ./mail/rspamd.nix
    ./mail/clamav.nix
  ];

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.mail-directory} 775 ${cfg.mail-user} ${cfg.mail-group} - -"
      "d ${cfg.state-directory} 775 root ${cfg.mail-group} - -"
    ];

    networking.firewall = {
      allowedTCPPorts = [ 25 110 143 587 993 995 ];
    };
    
    users = {
      users = {
        ${cfg.mail-user} = {
          isSystemUser = true;
          uid = cfg.mail-user-id;
          group = cfg.mail-group;
        };
      };

      groups = {
        ${cfg.mail-group} = {
          members = [ cfg.mail-user ];
        };
      };
    };
  };
}
