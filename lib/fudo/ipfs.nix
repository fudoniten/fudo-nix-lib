{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.ipfs;

  user-group-entry = group: user:
    nameValuePair user { extraGroups = [ group ]; };

in {
  options.fudo.ipfs = with types; {
    enable = mkEnableOption "Fudo IPFS";

    users = mkOption {
      type = listOf str;
      description = "List of users with IPFS access.";
      default = [ ];
    };

    user = mkOption {
      type = str;
      description = "User as which to run IPFS user.";
      default = "ipfs";
    };

    group = mkOption {
      type = str;
      description = "Group as which to run IPFS user.";
      default = "ipfs";
    };

    api-address = mkOption {
      type = str;
      description = "Address on which to listen for requests.";
      default = "/ip4/127.0.0.1/tcp/5001";
    };

    automount = mkOption {
      type = bool;
      description = "Whether to automount /ipfs and /ipns on boot.";
      default = true;
    };

    data-dir = mkOption {
      type = str;
      description = "Path to store data for IPFS.";
      default = "/var/lib/ipfs";
    };
  };

  config = mkIf cfg.enable {

    users.users =
      mapAttrs user-group-entry config.instance.local-users;

    services.ipfs = {
      enable = true;
      apiAddress = cfg.api-address;
      autoMount = cfg.automount;
      enableGC = true;
      user = cfg.user;
      group = cfg.group;
      dataDir = cfg.data-dir;
    };
  };
}
