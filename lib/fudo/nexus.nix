{ config, lib, pkgs, ... }:

with pkgs.lib;
let
  domainOpts = { name, ... }: {
    options = with types; {
      domain = mkOption {
        type = str;
        default = name;
      };

      servers = mkOption {
        type = listOf str;
        description = "List of servers for this Nexus domain.";
      };

      dns-servers = mkOption {
        type = listOf str;
        description = "List of DNS servers for this Nexus domain.";
      };

      gssapi-realm = mkOption {
        type = nullOr str;
        default = null;
      };

      trusted-networks = mkOption {
        type = listOf str;
        default = [ ];
      };

      records = let
        recordOpts = { name, ... }: {
          options = {
            name = mkOption {
              type = str;
              description = "Name of this record.";
              default = name;
            };

            type = mkOption {
              type = str;
              description = "Record type of this record.";
            };

            content = mkOption {
              type = str;
              description = "Data associated with this record.";
            };
          };
        };
      in mkOption {
        type = listOf (submodule recordOpts);
        default = [ ];
      };
    };
  };

in {
  options.fudo.nexus = with types; {
    domains = mkOption {
      type = attrsOf (submodule domainOpts);
      description = "Nexus domain configurations.";
      default = { };
    };
  };
}
