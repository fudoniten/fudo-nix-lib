{ config, pkgs, lib, ... }:

with lib;
let cfg = config.fudo.mail-server;

in {
  options.fudo.mail-server.clamav = {
    enable = mkOption {
      description = "Enable virus scanning with ClamAV.";
      type = types.bool;
      default = true;
    };
  };

  config = mkIf (cfg.enable && cfg.clamav.enable) {

    services.clamav = {
      daemon = {
        enable = true;
        settings = { PhishingScanURLs = "no"; };
      };
      updater.enable = true;
    };
  };
}
