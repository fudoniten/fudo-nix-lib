{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.backplane.dns;

  powerdns-conf-dir = "${cfg.powerdns.home}/conf.d";

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

  databaseOpts = { ... }: {
    options = with types; {
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
        description = "File containing password for database user.";
      };
    };
  };

in {
  options.fudo.backplane = with types; {

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

    backplane-host = mkOption {
      type = types.str;
      description = "Hostname of the backplane XMPP server.";
    };

    dns = {
      enable = mkEnableOption "Enable backplane dynamic DNS server.";

      port = mkOption {
        type = port;
        description = "Port on which to serve authoritative DNS requests.";
        default = 53;
      };

      listen-v4-addresses = mkOption {
        type = listOf str;
        description = "IPv4 addresses on which to listen for dns requests.";
        default = [ "0.0.0.0" ];
      };

      listen-v6-addresses = mkOption {
        type = listOf str;
        description = "IPv6 addresses on which to listen for dns requests.";
        example = [ "[abcd::1]" ];
        default = [ ];
      };

      required-services = mkOption {
        type = listOf str;
        description =
          "A list of services required before the DNS server can start.";
        default = [ ];
      };

      user = mkOption {
        type = str;
        description = "User as which to run DNS backplane listener service.";
        default = "backplane-dns";
      };

      group = mkOption {
        type = str;
        description = "Group as which to run DNS backplane listener service.";
        default = "backplane-dns";
      };

      database = mkOption {
        type = submodule databaseOpts;
        description = "Database settings for the DNS server.";
      };

      powerdns = {
        home = mkOption {
          type = str;
          description = "Directory at which to store powerdns configuration and state.";
          default = "/run/backplane-dns/powerdns";
        };

        user = mkOption {
          type = str;
          description = "Username as which to run PowerDNS.";
          default = "backplane-powerdns";
        };

        database = mkOption {
          type = submodule databaseOpts;
          description = "Database settings for the DNS server.";
        };
      };

      backplane-role = {
        role = mkOption {
          type = types.str;
          description = "Backplane XMPP role name for the DNS server.";
          default = "service-dns";
        };

        password-file = mkOption {
          type = types.str;
          description = "File containing XMPP password for backplane role.";
        };
      };
    };
  };
}
