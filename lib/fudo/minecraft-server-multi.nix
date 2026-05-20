{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.services.minecraft.server;

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
  ];

  serverOpts = { name, ... }: {
    options = with types; {
      enable = mkOption {
        type = bool;
        description = "Enable this server instance.";
        default = true;
      };

      package = mkOption {
        type = package;
        description = "Minecraft server package to use.";
        default = pkgs.minecraft-current;
      };

      world-name = mkOption {
        type = str;
        description = "Name of the server world (used in saves etc).";
        default = name;
      };

      motd = mkOption {
        type = str;
        description = "Welcome message for newcomers.";
        default = "Welcome to ${name}!";
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

      allow-pvp = mkOption {
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
  };

  sanitizeName = name: replaceStrings [ " " ] [ "_" ] name;

  serverStateDir = name: "${cfg.state-directory}/${sanitizeName name}";

  toProps = attrs:
    let
      boolToStr = v: if v then "true" else "false";
      toVal = v: if isBool v then boolToStr v else toString v;
    in concatStringsSep "\n" (mapAttrsToList (k: v: "${k}=${toVal v}") attrs);

  genPropsFile = name: serverConf:
    let
      seedAttr = optionalAttrs (serverConf.world-seed != null) {
        level-seed = serverConf.world-seed;
      };
      props = {
        level-name = serverConf.world-name;
        motd = serverConf.motd;
        difficulty = serverConf.difficulty;
        gamemode = serverConf.game-mode;
        enable-cheats = serverConf.allow-cheats;
        server-port = serverConf.port;
        "query.port" = serverConf.query-port;
        enable-query = true;
        "rcon.port" = serverConf.rcon-port;
        pvp = serverConf.allow-pvp;
      } // seedAttr;
    in pkgs.writeText "mc-${sanitizeName name}.properties" (toProps props);

in {
  options.fudo.services.minecraft.server = with types; {
    enable = mkEnableOption "multi-instance vanilla Minecraft server";

    state-directory = mkOption {
      type = str;
      description = "Path at which to store Minecraft server data.";
    };

    user = mkOption {
      type = str;
      description = "User as which to run the Minecraft servers.";
      default = "minecraft";
    };

    group = mkOption {
      type = str;
      description = "Group as which to run the Minecraft servers.";
      default = "minecraft";
    };

    servers = mkOption {
      type = attrsOf (submodule serverOpts);
      description = "Minecraft server instances to run.";
      default = { };
    };
  };

  config = mkIf cfg.enable {
    users = {
      users."${cfg.user}" = {
        isSystemUser = true;
        home = cfg.state-directory;
        group = cfg.group;
        createHome = true;
      };
      groups."${cfg.group}" = { members = [ cfg.user ]; };
    };

    networking.firewall.allowedTCPPorts = concatMap
      (s: [ s.port s.query-port s.rcon-port ])
      (attrValues cfg.servers);

    systemd = {
      tmpfiles.rules = mapAttrsToList (name: _:
        "d ${serverStateDir name} 0700 ${cfg.user} ${cfg.group} - -")
        cfg.servers;

      services = mapAttrs' (name: serverConf:
        let
          safeName = sanitizeName name;
          svcName = "minecraft-${safeName}";
          stateDir = serverStateDir name;

          preStartScript =
            let
              propsFile = genPropsFile name serverConf;
              eulaFile = pkgs.writeText "mc-${safeName}-eula.txt" "eula=true";
            in pkgs.writeShellScript "mc-init-${safeName}.sh" ''
              cp -f ${propsFile} ${stateDir}/server.properties
              cp -f ${eulaFile} ${stateDir}/eula.txt
              chmod u+w ${stateDir}/server.properties
            '';

          startScript =
            let
              mem = "${toString serverConf.allocated-memory}G";
              flags = commonFlags
                ++ [ "-Xms${mem}" "-Xmx${mem}" ]
                ++ optionals (serverConf.allocated-memory >= 12) highMemFlags;
            in pkgs.writeShellScript "mc-start-${safeName}.sh"
              "${serverConf.package}/bin/minecraft-server ${concatStringsSep " " flags}";

        in nameValuePair svcName {
          enable = serverConf.enable;
          description = "${name} Minecraft Server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          requires = [ "network-online.target" ];
          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = stateDir;
            ExecStartPre = "${preStartScript}";
            ExecStart = "${startScript}";
            Restart = "always";
            NoNewPrivileges = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectControlGroups = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
            RestrictRealtime = true;
            RestrictNamespaces = true;
            ReadWritePaths = [ cfg.state-directory ];
          };
        }) cfg.servers;
    };
  };
}
