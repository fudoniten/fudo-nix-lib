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
        description = "Whether to allow cheat/operator commands on the server.";
        default = false;
      };

      allow-pvp = mkOption {
        type = bool;
        description = "Whether players can attack each other (PvP).";
        default = false;
      };

      keep-inventory = mkOption {
        type = bool;
        description = "Whether players keep their inventory on death (keepInventory gamerule).";
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

      rcon-password = mkOption {
        type = str;
        description = "Password for the RCON remote console. Used to apply server-side gamerules (e.g. keepInventory). Change this from the default!";
        default = "changeme";
      };

      world-seed = mkOption {
        type = nullOr int;
        description = "Seed to use while generating the world.";
        default = null;
      };

      on-demand = mkOption {
        type = bool;
        description = ''
          Start the server on-demand when a player connects to the port, rather than
          running all the time. The server shuts down automatically after
          idle-timeout-hours of inactivity. When enabled, Minecraft internally binds
          to port + 10000; the public port is handled by a lightweight proxy.
        '';
        default = false;
      };

      idle-timeout-hours = mkOption {
        type = int;
        description = "Hours of player inactivity before an on-demand server shuts down.";
        default = 6;
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

  # On-demand servers bind to an internal port so the proxy can own the public port.
  serverListenPort = serverConf:
    if serverConf.on-demand then serverConf.port + 10000 else serverConf.port;

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
        server-port = serverListenPort serverConf;
        "query.port" = serverConf.query-port;
        enable-query = true;
        "rcon.port" = serverConf.rcon-port;
        "rcon.password" = serverConf.rcon-password;
        enable-rcon = true;
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

    # Only the game port is opened externally. RCON and query are localhost-only
    # and must not be reachable from the internet.
    networking.firewall.allowedTCPPorts = map (s: s.port)
      (filter (s: s.enable) (attrValues cfg.servers));

    systemd =
      let
        enabledServers = filterAttrs (_: s: s.enable) cfg.servers;
        onDemandServers = filterAttrs (_: s: s.on-demand) enabledServers;

        genMainService = name: serverConf:
          let
            safeName = sanitizeName name;
            svcName = "minecraft-${safeName}";
            stateDir = serverStateDir name;

            propsFile = genPropsFile name serverConf;
            eulaFile = pkgs.writeText "mc-${safeName}-eula.txt" "eula=true";

            preStartScript = pkgs.writeShellScript "mc-init-${safeName}.sh" ''
              cp -f ${propsFile} ${stateDir}/server.properties
              cp -f ${eulaFile} ${stateDir}/eula.txt
              chmod u+w ${stateDir}/server.properties
              ${optionalString serverConf.on-demand
                "date +%s > ${stateDir}/.last-player-time"}
            '';

            startScript =
              let
                mem = "${toString serverConf.allocated-memory}G";
                flags =
                  # Required by JNA (used by OSHI for hardware telemetry). Without
                  # this, newer JVMs will block native access entirely.
                  [ "--enable-native-access=ALL-UNNAMED"
                  # JNA extracts a native .so to a tmpdir before loading it. The
                  # state directory is typically noexec, so we redirect JNA to the
                  # service's runtime directory (/run/...) which is always exec.
                    "-Djna.tmpdir=/run/${svcName}" ]
                  ++ commonFlags
                  ++ [ "-Xms${mem}" "-Xmx${mem}" ]
                  ++ optionals (serverConf.allocated-memory >= 12) highMemFlags;
              in pkgs.writeShellScript "mc-start-${safeName}.sh"
                "${serverConf.package}/bin/minecraft-server ${concatStringsSep " " flags}";

            # Polls until RCON is ready, then syncs gamerules declared in config.
            postStartScript = pkgs.writeShellScript "mc-post-${safeName}.sh" ''
              for attempt in $(seq 1 60); do
                if ${pkgs.mcrcon}/bin/mcrcon \
                    -H 127.0.0.1 \
                    -P ${toString serverConf.rcon-port} \
                    -p ${escapeShellArg serverConf.rcon-password} \
                    "list" >/dev/null 2>&1
                then
                  ${pkgs.mcrcon}/bin/mcrcon \
                    -H 127.0.0.1 \
                    -P ${toString serverConf.rcon-port} \
                    -p ${escapeShellArg serverConf.rcon-password} \
                    "gamerule minecraft:keep_inventory ${if serverConf.keep-inventory then "true" else "false"}"
                  exit 0
                fi
                sleep 5
              done
              echo "Warning: timed out waiting for RCON; gamerules may not be applied." >&2
            '';

          in nameValuePair svcName {
            description = "${name} Minecraft Server";
            wantedBy = optionals (!serverConf.on-demand) [ "multi-user.target" ];
            # Start the idle-check timer alongside this service (on-demand only).
            wants = optionals serverConf.on-demand [ "${svcName}-idle-check.timer" ];
            after = [ "network-online.target" ];
            requires = [ "network-online.target" ];
            serviceConfig = {
              User = cfg.user;
              Group = cfg.group;
              WorkingDirectory = stateDir;
              ExecStartPre = "${preStartScript}";
              ExecStart = "${startScript}";
              ExecStartPost = "${postStartScript}";
              # On-demand servers are restarted by socket activation, not by systemd.
              Restart = if serverConf.on-demand then "no" else "always";
              RuntimeDirectory = svcName;
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
          };

        # Proxy service: activated by the socket, waits for Minecraft to be
        # RCON-ready before accepting player connections, then forwards traffic.
        # Stops when Minecraft stops (bindsTo), which re-arms the socket for the
        # next connection.
        genProxyService = name: serverConf:
          let
            safeName = sanitizeName name;
            svcName = "minecraft-${safeName}";
            internalPort = toString (serverConf.port + 10000);

            waitForRconScript = pkgs.writeShellScript "mc-wait-rcon-${safeName}.sh" ''
              for attempt in $(seq 1 120); do
                if ${pkgs.mcrcon}/bin/mcrcon \
                    -H 127.0.0.1 \
                    -P ${toString serverConf.rcon-port} \
                    -p ${escapeShellArg serverConf.rcon-password} \
                    "list" >/dev/null 2>&1
                then
                  exit 0
                fi
                sleep 5
              done
              echo "Timed out waiting for ${name} RCON" >&2
              exit 1
            '';

          in nameValuePair "${svcName}-proxy" {
            description = "${name} Minecraft On-Demand Proxy";
            # BindsTo implies Requires: starts Minecraft when proxy starts,
            # and stops proxy when Minecraft stops.
            bindsTo = [ "${svcName}.service" ];
            after = [ "${svcName}.service" ];
            serviceConfig = {
              # Wait for Minecraft to finish starting before accepting connections.
              # Clients queue in the kernel socket buffer during this time.
              ExecStartPre = "${waitForRconScript}";
              ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${internalPort}";
              # Allow up to 10 minutes for a cold-start world load.
              TimeoutStartSec = 600;
              NoNewPrivileges = true;
              PrivateDevices = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
              RestrictRealtime = true;
            };
          };

        # Socket unit: listens on the public game port and activates the proxy
        # service on first connection.
        genProxySocket = name: serverConf:
          let safeName = sanitizeName name;
          in nameValuePair "minecraft-${safeName}-proxy" {
            description = "${name} Minecraft On-Demand Socket";
            wantedBy = [ "sockets.target" ];
            socketConfig = {
              ListenStream = serverConf.port;
              Accept = false;
            };
          };

        # Idle-check service: polls the player count via RCON every 30 minutes.
        # Shuts the server down gracefully once nobody has been online for
        # idle-timeout-hours.
        genIdleCheckService = name: serverConf:
          let
            safeName = sanitizeName name;
            svcName = "minecraft-${safeName}";
            stateDir = serverStateDir name;
            idleTimeoutSecs = toString (serverConf.idle-timeout-hours * 3600);

            idleCheckScript = pkgs.writeShellScript "mc-idle-check-${safeName}.sh" ''
              LAST_PLAYER_FILE="${stateDir}/.last-player-time"
              IDLE_TIMEOUT=${idleTimeoutSecs}

              if ! systemctl is-active --quiet "${svcName}.service"; then
                exit 0
              fi

              PLAYER_LIST=$(${pkgs.mcrcon}/bin/mcrcon \
                -H 127.0.0.1 \
                -P ${toString serverConf.rcon-port} \
                -p ${escapeShellArg serverConf.rcon-password} \
                "list" 2>/dev/null) || exit 0

              PLAYER_COUNT=$(echo "$PLAYER_LIST" | awk '/There are/{print $3}')

              if [ "''${PLAYER_COUNT:-0}" -gt 0 ] 2>/dev/null; then
                date +%s > "$LAST_PLAYER_FILE"
                exit 0
              fi

              if [ -f "$LAST_PLAYER_FILE" ]; then
                LAST_TIME=$(cat "$LAST_PLAYER_FILE")
                NOW=$(date +%s)
                IDLE_SECONDS=$((NOW - LAST_TIME))

                if [ "$IDLE_SECONDS" -ge "$IDLE_TIMEOUT" ]; then
                  echo "${name}: idle for ''${IDLE_SECONDS}s (limit ${idleTimeoutSecs}s), shutting down."
                  ${pkgs.mcrcon}/bin/mcrcon \
                    -H 127.0.0.1 \
                    -P ${toString serverConf.rcon-port} \
                    -p ${escapeShellArg serverConf.rcon-password} \
                    "say Server shutting down due to inactivity. Goodbye!" 2>/dev/null || true
                  sleep 30
                  systemctl --no-block stop "${svcName}.service"
                fi
              else
                date +%s > "$LAST_PLAYER_FILE"
              fi
            '';

          in nameValuePair "${svcName}-idle-check" {
            description = "${name} Minecraft Idle Check";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${idleCheckScript}";
              ReadWritePaths = [ cfg.state-directory ];
            };
          };

        genIdleCheckTimer = name: serverConf:
          let
            safeName = sanitizeName name;
            svcName = "minecraft-${safeName}";
          in nameValuePair "${svcName}-idle-check" {
            description = "${name} Minecraft Idle Check Timer";
            # Stop this timer when Minecraft stops; it is started by the Minecraft
            # service via wants = [...].
            partOf = [ "${svcName}.service" ];
            timerConfig = {
              OnActiveSec = "30min";
              OnUnitActiveSec = "30min";
            };
          };

      in {
        tmpfiles.rules = mapAttrsToList (name: _:
          "d ${serverStateDir name} 0700 ${cfg.user} ${cfg.group} - -")
          enabledServers;

        services =
          (mapAttrs' genMainService enabledServers)
          // (mapAttrs' genProxyService onDemandServers)
          // (mapAttrs' genIdleCheckService onDemandServers);

        sockets = mapAttrs' genProxySocket onDemandServers;

        timers = mapAttrs' genIdleCheckTimer onDemandServers;
      };
  };
}
