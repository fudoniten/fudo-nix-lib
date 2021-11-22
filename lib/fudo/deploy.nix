{ config, lib, pkgs, ... }:

with lib;
let
  site-cfg = config.fudo.sites.${config.instance.local-site};

in {
  config = {
    users.users.root.openssh.authorizedKeys.keys =
      mkIf (site-cfg.deploy-pubkeys != null)
        site-cfg.deploy-pubkeys;
  };
}
