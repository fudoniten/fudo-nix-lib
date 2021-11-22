{ config, lib, pkgs, ... }:

with lib;
let cfg = config.fudo.garbage-collector;

in {

  options.fudo.garbage-collector = {
    enable = mkEnableOption "Enable periodic NixOS garbage collection";

    timing = mkOption {
      type = types.str;
      default = "weekly";
      description =
        "Period (systemd format) at which to run garbage collector.";
    };

    age = mkOption {
      type = types.str;
      default = "30d";
      description = "Age of garbage to collect (eg. 30d).";
    };
  };

  config = mkIf cfg.enable {
    fudo.system.services.fudo-garbage-collector = {
      description = "Collect NixOS garbage older than ${cfg.age}.";
      onCalendar = cfg.timing;
      type = "oneshot";
      script =
        "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than ${cfg.age}";
      addressFamilies = [ ];
    };
  };
}
