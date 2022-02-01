{ config, lib, pkgs, ... } @ toplevel:

with lib;
let
  cfg = config.fudo.backplane.dns;

  backplane-dns-home = "${config.instance.service-home}/backplane-dns";

in {
  options.fudo.backplane.dns = with types; {
    enable = mkEnableOption "Enable DNS backplane service.";

    required-services = mkOption {
      type = listOf str;
      description = "List of systemd units on which the DNS backplane job depends.";
      default = [ ];
    };

    backplane-server = mkOption {
      type = str;
      description = "Backplane XMPP server hostname.";
      default = toplevel.config.fudo.backplane.backplane-hostname;
    };

    user = mkOption {
      type = str;
      description = "User as which to run the backplane dns service.";
      default = "backplane-dns";
    };

    group = mkOption {
      type = str;
      description = "Group as which to run the backplane dns service.";
      default = "backplane-dns";
    };

    database = {
      host = mkOption {
        type = str;
        description = "Hostname or IP of the PostgreSQL server.";
      };

      database = mkOption {
        type = str;
        description = "Database to use for DNS backplane.";
        default = "backplane_dns";
      };

      username = mkOption {
        type = str;
        description = "Database user for DNS backplane.";
        default = "backplane_dns";
      };

      password-file = mkOption {
        type = str;
        description = "File containing password for DNS backplane database user.";
      };

      ssl-mode = mkOption {
        type = enum ["no" "yes" "full" "try" "require"];
        description = "SSL connection mode.";
        default = "require";
      };
    };

    backplane-role = {
      role = mkOption {
        type = str;
        description = "Backplane XMPP role name for DNS backplane job.";
        default = "service-dns";
      };

      password-file = mkOption {
        type = str;
        description = "Password file for backplane XMPP for DNS backplane job.";
      };
    };
  };

  config = mkIf cfg.enable {
    users = {
      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = backplane-dns-home;
        createHome = true;
      };
      groups.${cfg.group} = {
        members = [ cfg.user ];
      };
    };

    fudo.system.services = {
      backplane-dns = {
        description = "Fudo DNS Backplane Server";
        restartIfChanged = true;
        path = with pkgs; [ backplane-dns-server ];
        execStart = "${pkgs.backplane-dns-server}/bin/launch-backplane-dns.sh";
        #pidFile = "/run/backplane/dns.pid";
        partOf = [ "backplane-dns.target" ];
        wantedBy = [ "multi-user.target" ];
        requires = cfg.required-services;
        user = cfg.user;
        group = cfg.group;
        memoryDenyWriteExecute = false; # Needed becuz Lisp
        readWritePaths = [ backplane-dns-home ];
        privateNetwork = false;
        addressFamilies = [ "AF_INET" "AF_INET6" ];
        environment = {
          FUDO_DNS_BACKPLANE_XMPP_HOSTNAME = cfg.backplane-server;
          FUDO_DNS_BACKPLANE_XMPP_USERNAME = cfg.backplane-role.role;
          FUDO_DNS_BACKPLANE_XMPP_PASSWORD_FILE = cfg.backplane-role.password-file;

          FUDO_DNS_BACKPLANE_DATABASE_HOSTNAME = cfg.database.host;
          FUDO_DNS_BACKPLANE_DATABASE_NAME = cfg.database.database;
          FUDO_DNS_BACKPLANE_DATABASE_USERNAME =
            cfg.database.username;
          FUDO_DNS_BACKPLANE_DATABASE_PASSWORD_FILE =
            cfg.database.password-file;
          FUDO_DNS_BACKPLANE_DATABASE_USE_SSL = cfg.database.ssl-mode;

          CL_SOURCE_REGISTRY =
            pkgs.lib.lisp.lisp-source-registry pkgs.backplane-dns-server;

          LD_LIBRARY_PATH = "${pkgs.openssl.out}/lib";
        };
      };
    };
  };
}
