{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.minecraft-server;

in {
  options.fudo.minecraft-server = {
    enable = mkEnableOption "Start a minecraft server.";

    package = mkOption {
      type = types.package;
      description = "Minecraft package to use.";
      default = pkgs.minecraft-server_1_15_1;
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
    };

    game-mode = mkOption {
      type = types.enum ["survival" "creative" "adventure" "spectator"];
      description = "Game mode of the server.";
      default = "survival";
    };

    difficulty = mkOption {
      type = types.int;
      description = "Difficulty level, where 0 is peaceful and 3 is hard.";
      default = 2;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ];

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
      };
    };
  };
}
