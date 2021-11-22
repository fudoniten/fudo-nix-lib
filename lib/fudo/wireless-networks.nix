{ config, lib, pkgs, ... }:

with lib;
let
  networkOpts = { network, ... }: {
    options = {
      network = mkOption {
        type = types.str;
        description = "Name of wireless network.";
        default = network;
      };

      key = mkOption {
        type = types.str;
        description = "Secret key for wireless network.";
      };
    };
  };

in {
  options.fudo.wireless-networks = mkOption {
    type = with types; attrsOf (submodule networkOpts);
    description = "A map of wireless networks to attributes (including key).";
    default = { };
  };

  config = {
    networking.wireless.networks =
      mapAttrs (network: networkOpts: { psk = networkOpts.key; })
      config.fudo.wireless-networks;
  };
}
