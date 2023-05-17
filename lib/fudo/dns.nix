{ lib, config, pkgs, ... }:

with lib;
let
  cfg = config.fudo.dns;

  join-lines = concatStringsSep "\n";

  domainOpts = { name, ... }: {
    options = with types; {
      domain = mkOption {
        type = str;
        description = "Domain name.";
        default = name;
      };

      dnssec = mkOption {
        type = bool;
        description = "Enable DNSSEC security for this zone.";
        default = true;
      };

      ksk = {
        key-file = mkOption {
          type = str;
          description = "Key-signing key for this zone.";
        };
      };

      zone-definition = mkOption {
        type = submodule (import ../types/zone-definition.nix);
        description =
          "Definition of network zone to be served by local server.";
      };
    };
  };

in {

  options.fudo.dns = with types; {
    enable = mkEnableOption "Enable master DNS services.";

    identity = mkOption {
      type = str;
      description = "The identity (CH TXT ID.SERVER) of this host.";
    };

    domains = mkOption {
      type = attrsOf (submodule domainOpts);
      default = { };
      description = "A map of domain to domain options.";
    };

    listen-ips = mkOption {
      type = listOf str;
      description = "A list of IPs on which to listen for DNS queries.";
      example = [ "1.2.3.4" ];
    };

    state-directory = mkOption {
      type = str;
      description =
        "Path at which to store nameserver state, including DNSSEC keys.";
      default = "/var/lib/nsd";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };

    # fileSystems."/var/lib/nsd" = {
    #   device = cfg.state-directory;
    #   options = [ "bind" ];
    # };

    fudo = {
      nsd = {
        enable = true;
        identity = cfg.identity;
        interfaces = cfg.listen-ips;
        stateDirectory = cfg.state-directory;
        zones = mapAttrs' (dom: dom-cfg:
          let net-cfg = dom-cfg.zone-definition;
          in nameValuePair "${dom}." {
            dnssec = dom-cfg.dnssec;

            ksk.keyFile = dom-cfg.ksk.key-file;

            data =
              pkgs.lib.dns.zoneToZonefile config.instance.build-timestamp dom
              dom-cfg.zone-definition;

          }) cfg.domains;
      };
    };
  };
}
