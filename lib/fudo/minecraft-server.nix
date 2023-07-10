{ config, lib, pkgs, ... }:

with lib;
let cfg = config.fudo.minecraft-server;

in {
  options.fudo.minecraft-server = with types; {
    enable = mkEnableOption "Start a minecraft server.";

    package = mkOption {
      type = package;
      description = "Minecraft package to use.";
      default = pkgs.minecraft-current;
    };

    data-dir = mkOption {
      type = path;
      description = "Path at which to store minecraft data.";
    };

    world-name = mkOption {
      type = str;
      description = "Name of the server world (used in saves etc).";
    };

    motd = mkOption {
      type = str;
      description = "Welcome message for newcomers.";
      default = "Welcome to Minecraft! Have fun building...";
    };

    game-mode = mkOption {
      type = enum [ "survival" "creative" "adventure" "spectator" ];
      description = "Game mode of the server.";
      default = "survival";
    };

    difficulty = mkOption {
      type = int;
      description = "Difficulty level, where 0 is peaceful and 3 is hard.";
      default = 2;
    };

    allow-cheats = mkOption {
      type = bool;
      default = false;
    };

    allocated-memory = mkOption {
      type = int;
      description = "Memory (in GB) to allocate to the Minecraft server.";
      default = 2;
    };

    port = mkOption {
      type = port;
      description = "Port on which to run the Minecraft server.";
      default = 25565;
    };

    query-port = mkOption {
      type = port;
      description = "Port for queries.";
      default = 25566;
    };

    rcon-port = mkOption {
      type = port;
      description = "Port for remote commands.";
      default = 25567;
    };

    world-seed = mkOption {
      type = nullOr int;
      description = "Seed to use while generating the world.";
      default = null;
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
        level-seed = cfg.world-seed;
        motd = cfg.motd;
        difficulty = cfg.difficulty;
        gamemode = cfg.game-mode;
        allow-cheats = cfg.allow-cheats;
        server-port = cfg.port;
        "rcon.port" = cfg.rcon-port;
        "query.port" = cfg.query-port;
        pvp = cfg.allow-pvp;
      };
      jvmOpts = let
        opts = [
          "-Xms${toString cfg.allocated-memory}G"
          "-Xmx${toString cfg.allocated-memory}G"
          "-XX:+UseG1GC"
          "-XX:+ParallelRefProcEnabled"
          "-XX:MaxGCPauseMillis=200"
          "-XX:+UnlockExperimentalVMOptions"
          "-XX:+DisableExplicitGC"
          "-XX:+AlwaysPreTouch"
          "-XX:G1NewSizePercent=30"
          "-XX:G1MaxNewSizePercent=40"
          "-XX:G1HeapRegionSize=8M"
          "-XX:G1ReservePercent=20"
          "-XX:G1HeapWastePercent=5"
          "-XX:G1MixedGCCountTarget=4"
          "-XX:InitiatingHeapOccupancyPercent=15"
          "-XX:G1MixedGCLiveThresholdPercent=90"
          "-XX:G1RSetUpdatingPauseTimePercent=5"
          "-XX:SurvivorRatio=32"
          "-XX:+PerfDisableSharedMem"
          "-XX:MaxTenuringThreshold=1"
        ] ++ (optionals (cfg.allocated-memory >= 12) [
          "-XX:G1NewSizePercent=40"
          "-XX:G1MaxNewSizePercent=50"
          "-XX:G1HeapRegionSize=16M"
          "-XX:G1ReservePercent=15"
          "-XX:InitiatingHeapOccupancyPercent=20"
        ]);
      in concatStringsSep " " opts;
    };
  };
}
