{ config, lib, pkgs, ... }:

with lib;
let cfg = config.fudo.system;

in {
  options.fudo.system = with types; {
    # DO THIS MANUALLY since NixOS sux at making a reasonable /etc/hosts
    hostfile-entries = mkOption {
      type = attrsOf (listOf str);
      description = "Map of extra IP addresses to hostnames for /etc/hosts";
      default = { };
      example = { "10.0.0.3" = [ "my-host" "my-host.my.domain" ]; };
    };
  };
}
