{ config, lib, pkgs, ... }:

with lib;
let cfg = config.fudo.minecraft-server;

in {
  options.fudo.minecraft-server = {
    enable = mkEnableOption "Start a minecraft server.";

    package = mkOption {
      type = types.package;
      description = "Minecraft package to use.";
      default = pkgs.minecraft-current;
    };

    data-dir = mkOption {
      type = types.path;
      description = "Path at which to store minecraft data.";
    };

    world-name = mkOption {
      type = types.str;
      description = "Name of the server world (used in saves etc).";
    };

    motd = mkOption {
      type = types.str;
      description = "Welcome message for newcomers.";
      default = "Welcome to Minecraft! Have fun building...";
    };

    game-mode = mkOption {
      type = types.enum [ "survival" "creative" "adventure" "spectator" ];
      description = "Game mode of the server.";
      default = "survival";
    };

    difficulty = mkOption {
      type = types.int;
      description = "Difficulty level, where 0 is peaceful and 3 is hard.";
      default = 2;
    };

    allow-cheats = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    services.minecraft-server = {
      enable = true;
      package = cfg.package;
      dataDir = cfg.data-dir;
      eula = true;
      declarative = true;
      serverProperties = {
        level-name = cfg.world-name;
        motd = cfg.motd;
        difficulty = cfg.difficulty;
        gamemode = cfg.game-mode;
        allow-cheats = true;
      };
    };
  };
}
