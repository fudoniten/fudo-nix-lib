{ config, lib, pkgs, ... }:

with pkgs.lib;
let
  domainOpts = { name, ... }: {
    options = with types; {
      domain = mkOption {
        type = str;
        default = name;
      };

      server = mkOption {
        type = str;
        description = "Primary server for this Nexus domain.";
      };

      secondary-dns-servers = mkOption {
        type = listOf str;
        description = "List of secondary DNS servers for this Nexus domain.";
      };

      gssapi-realm = mkOption {
        type = nullOr str;
        default = null;
      };

      trusted-networks = mkOption {
        type = listOf str;
        default = [ ];
      };

      challenge-public-keys = mkOption {
        type = attrsOf str;
        description = ''
          Map of challenge-client name to Ed25519 public key, passed
          straight through to this domain's Nexus server as
          `services.nexus.server.challenge-public-keys` (upstream
          `fudoniten/nexus`, /api/v3).

          A challenge client authenticates ACME DNS-01 requests with a
          keypair rather than the legacy shared HMAC secret. The public
          half is not sensitive -- it is meant to sit in a plaintext data
          file like this one, the same way a host's `ssh-pubkeys` does --
          so it belongs here rather than behind Aegis or any other secrets
          pipeline.  Generate the keypair with `nexus-generate-key
          --keypair`; put the private half wherever the client (currently
          only Kubernetes) reads its own secrets from.
        '';
        default = { };
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
