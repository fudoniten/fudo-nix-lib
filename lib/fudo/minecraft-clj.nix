{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.minecraft-clj;

  papermcWithPlugins = pkgs.buildEnv {
    name = "papermcWithPlugins";
    paths = with pkgs; [ papermc witchcraft-plugin-current ];
  };

  highMemFlags = [
    "-XX:G1NewSizePercent=40"
    "-XX:G1MaxNewSizePercent=50"
    "-XX:G1HeapRegionSize=16M"
    "-XX:G1ReservePercent=15"
    "-XX:InitiatingHeapOccupancyPercent=20"
  ];

  commonFlags = [
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
    "-Dusing.aikars.flags=https://mcflags.emc.gs"
    "-Daikars.new.flags=true"
  ];

  worldOpts = { name, ... }:
    let world-name = name;
    in {
      options = with types; {
        enable = mkEnableOption "Enable this world.";

        world-name = mkOption {
          type = str;
          description = "Name of this world.";
          default = world-name;
        };

        port = mkOption {
          type = port;
          description = "Port on which to run this Minecraft world.";
          default = 25565;
        };

        difficulty = mkOption {
          type = enum [ "peaceful" "easy" "medium" "hard" ];
          description = "Difficulty setting of this server.";
          default = "medium";
        };

        game-mode = mkOption {
          type = enum [ "survival" "creative" "adventure" "spectator" ];
          description = "Game mode of the server.";
          default = "survival";
        };

        hardcore = mkOption {
          type = bool;
          description = "Give players only one life to live.";
          default = false;
        };

        world-seed = mkOption {
          type = nullOr int;
          description = "Seed to use while generating the world.";
          default = null;
        };

        motd = mkOption {
          type = str;
          description = "Message with which to greet users.";
          default = "Welcome to ${world-name}";
        };

        allow-cheats = mkOption {
          type = bool;
          description = "Allow cheats on this server.";
          default = true;
        };

        allocated-memory = mkOption {
          type = int;
          description = "Memory to allocate to Minecraft, in GB.";
          default = 4;
        };

        pvp = mkOption {
          type = bool;
          description = "Allow player-vs-player combat.";
          default = true;
        };
      };
    };

  validChar = c: !isNull (builtins.match "^[a-zA-Z0-9_-]$" c);

  swapSpace = replaceStrings [ " " ] [ "_" ];

  sanitizeName = name:
    concatStringsSep ""
    (filter validChar (stringToCharacters (swapSpace name)));

  worldStateDir = worldOpts:
    "${cfg.state-directory}/${sanitizeName worldOpts.world-name}";

  genProps = worldOpts: {
    level-name = worldOpts.world-name;
    level-seed = worldOpts.world-seed;
    motd = worldOpts.motd;
    difficulty = worldOpts.difficulty;
    gamemode = cfg.game-mode;
    allow-cheats = worldOpts.allowCheats;
    server-port = worldOpts.port;
    hardcore = worldOpts.hardcore;
    pvp = worldOpts.pvp;
  };

  toProps = attrs:
    let
      boolToString = v: if v then "true" else "false";
      toVal = v: if isBool v then boolToString v else toString v;
      toProp = k: v: "${k}=${toVal v}";
    in concatStringsSep "\n" (mapAttrsToList toProp attrs);

  genPropsFile = worldOpts:
    pkgs.writeText "mc-${sanitizeName worldOpts.world-name}.properties"
    (toProps (genProps worldOpts));

in {
  options.fudo.minecraft-clj = with types; {
    enable = mkEnableOption "Enable Minecraft server with Clojure repl.";

    state-directory = mkOption {
      type = str;
      description = "Path at which to store Minecraft data.";
    };

    user = mkOption {
      type = str;
      description = "User as which to run the minecraft server.";
      default = "minecraft-clj";
    };

    group = mkOption {
      type = str;
      description = "Group as which to run the minecraft server.";
      default = "minecraft-clj";
    };

    admins = mkOption {
      type = listOf str;
      description = "List of users to treat as administrators.";
      default = [ ];
    };

    worlds = mkOption {
      type = attrsOf (submodule worldOpts);
      description = "List of worlds to run on this server.";
      default = { };
    };
  };

  config = mkIf cfg.enable {
    users = {
      users."${cfg.user}" = {
        isSystemUser = true;
        home = cfg.data-dir;
        group = cfg.group;
        createHome = true;
      };
      groups."${cfg.group}" = { members = [ cfg.user ]; };
    };

    systemd = {
      tmpfiles.rules = map (worldOpts:
        "d ${worldStateDir worldOpts} 0700 ${cfg.user} ${cfg.group} - -")
        (attrValues cfg.worlds);

      services = mapAttrs' (_: worldOpts:
        let
          sanitizedName = sanitizeName worldOpts.world-name;
          serverName = "minecraft-clj-${sanitizedName}";
          stateDir = worldStateDir worldOpts;
          startScript = let
            admins-file = pkgs.writeText "${sanitizedName}-ops.txt"
              (concatStringsSep "\n" cfg.admins);
            props-file = genPropsFile worldOpts;

          in pkgs.writeShellScript "mc-initialize-${sanitizedName}.sh" ''
            cp -f ${admins-file} ${stateDir}/ops.txt
            cp -f ${props-file} ${stateDir}/server.properties
            chmod u+w ${stateDir}/server.properties
          '';

        in nameValuePair serverName {
          enable = worldOpts.enable;
          description =
            "${worldOpts.world-name} Minecraft Server with Clojure REPL";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = stateDir;
            ExecStart = let
              mem = "${toString worldOpts.allocated-memory}G";
              memFlags = [ "-Xms${mem}" "-Xmx${mem}" ];
              flags = commonFlags ++ memFlags
                ++ (optionals (cfg.allocated-memory >= 12) highMemFlags);
              flagStr = concatStringsSep " " flags;
            in "${pkgs.papermc}/bin/minecraft-server ${flagStr}";

            Restart = "always";
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectControlGroups = true;
            ProtectKernelModules = true;
            ProtectKernalTunables = true;
            RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
            RestrictRealtime = true;
            RestrictNamespaces = true;
          };
        }) cfg.worlds;
    };
  };
}
