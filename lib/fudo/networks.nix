{ config, lib, pkgs, ... }:

with lib;
with types;
let networkOpts = import ../types/network-definition.nix { inherit lib; };

in {
  options.fudo.networks = mkOption {
    type = attrsOf (submodule networkOpts);
    description = "A map of networks to network definitions.";
    default = { };
  };

  config = let
    domain-name = config.instance.local-domain;
    local-networks = map (network: "ip4:${network}")
      config.fudo.domains.${domain-name}.local-networks;
    local-net-string = concatStringsSep " " local-networks;
  in {
    fudo.networks.${domain-name}.verbatim-dns-records = [
      ''@ IN TXT "v=spf1 mx ${local-net-string} -all"''
      ''@ IN SPF "v=spf1 mx ${local-net-string} -all"''
    ];
  };
}
