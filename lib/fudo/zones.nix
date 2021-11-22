{ config, lib, pkgs, ... }:

with lib;
let
  zoneOpts =
    import ../types/zone-definition.nix { inherit lib; };
in {
  options.fudo.zones = with types; mkOption {
    type = attrsOf (submodule zoneOpts);
    description = "A map of network zone to zone definition.";
    default = { };
  };

  config = let
    domain-name = config.instance.local-domain;
    # FIXME: ipv6?
    local-networks = config.instance.local-networks;
    net-names = map (network: "ipv4:${network}")
      local-networks;
    local-net-string = concatStringsSep " " net-names;
  in {
    fudo.zones.${domain-name}.verbatim-dns-records = [
      ''@ IN TXT "v=spf1 mx ${local-net-string} -all"''
      ''@ IN SPF "v=spf1 mx ${local-net-string} -all"''
    ];
  };
}
