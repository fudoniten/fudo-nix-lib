{ config, lib, pkgs, ... }:

with lib;
let zoneOpts = import ../types/zone-definition.nix { inherit lib; };
in {
  options.fudo.zones = with types;
    mkOption {
      type = attrsOf (submodule zoneOpts);
      description = "A map of network zone to zone definition.";
      default = { };
    };

  config = let
    domainName = config.instance.local-domain;
    zoneName = config.fudo.domains."${domainName}".zone;
    isLocal = network: network == "::1" || hasPrefix "127." network;
    # FIXME: ipv6?
    localNetworks =
      filter (network: !(isLocal network)) config.instance.local-networks;
    makeName = network:
      if !isNull (builtins.match ":" network) then
        "ip6:${network}"
      else
        "ip4:${network}";
    netNames = map makeName localNetworks;
    localNetString = concatStringsSep " " netNames;
  in {
    fudo.zones."${zoneName}".verbatim-dns-records = [
      ''@ IN TXT "v=spf1 mx ${localNetString} -all"''
      ''@ IN SPF "v=spf1 mx ${localNetString} -all"''
    ];
  };
}
