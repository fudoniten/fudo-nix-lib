{ config, pkgs, lib, ... }:

with lib;
let cfg = config.fudo.mail-server;

in {
  options.fudo.mail-server.clamav = with types; {
    enable = mkOption {
      description = "Enable virus scanning with ClamAV.";
      type = bool;
      default = true;
    };

    state-directory = mkOption {
      type = str;
      description = "Path at which to store the ClamAV database.";
      default = "/var/lib/clamav";
    };
  };

  config = mkIf (cfg.enable && cfg.clamav.enable) {

    users = {
      users.clamav = {
        isSystemUser = true;
        group = "clamav";
      };
      groups.clamav = { members = [ "clamav" ]; };
    };

    systemd.tmpfiles.rules =
      [ "d ${cfg.clamav.state-directory} 0750 clamav clamav - -" ];

    services.clamav = {
      daemon = {
        enable = true;
        settings = {
          PhishingScanURLs = "no";
          DatabaseDirectory = mkForce cfg.clamav.state-directory;
          User = "clamav";
        };
      };
      updater = {
        enable = true;
        settings = { DatabaseDirectory = mkForce cfg.clamav.state-directory; };
      };
    };
  };
}
