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

      zone-definition = mkOption {
        type = submodule (import ../types/zone-definition.nix);
        description = "Definition of network zone to be served by local server.";
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
      description = "Path at which to store nameserver state, including DNSSEC keys.";
      default = "/var/lib/nsd";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
    
    fudo.nsd = {
      enable = true;
      identity = cfg.identity;
      interfaces = cfg.listen-ips;
      stateDir = cfg.state-directory;
      zones = mapAttrs' (dom: dom-cfg: let
        net-cfg = dom-cfg.zone-definition;
      in nameValuePair "${dom}." {
        dnssec = dom-cfg.dnssec;

        data =
          pkgs.lib.dns.zoneToZonefile
            config.instance.build-timestamp
            dom
            dom-cfg.zone-definition;

      }) cfg.domains;
    };
  };
}
