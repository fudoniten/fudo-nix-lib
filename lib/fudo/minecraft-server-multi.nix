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

  serverOpts = { name, config, ... }: {
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

      ops = mkOption {
        type = listOf str;
        description =
          "List of player names to grant operator status on the server.";
        default = [ ];
      };

      allow-pvp = mkOption {
        type = bool;
        description = "Whether players can attack each other (PvP).";
        default = false;
      };

      keep-inventory = mkOption {
        type = bool;
        description =
          "Whether players keep their inventory on death (keepInventory gamerule).";
        default = false;
      };

      spawn-protection = mkOption {
        type = bool;
        description = ''
          Whether to protect the area around the world spawn from being
          modified by non-operator players. When disabled (the default), the
          spawn-protection radius is set to 0.
        '';
        default = false;
      };

      white-list = mkOption {
        type = bool;
        description = ''
          Whether to restrict the server to players on the whitelist. Minecraft
          26.3 changed its own default to true, which rejects everyone unless
          the whitelist is maintained, so this is on only when `whitelist`
          declares one.
        '';
        default = config.whitelist != null;
        defaultText = literalExpression "whitelist != null";
      };

      whitelist = mkOption {
        type = nullOr (listOf str);
        description = ''
          Player names allowed on the server, or null to leave the whitelist
          alone. When set, the server's whitelist is synced to exactly this
          list over RCON after every start (and, in profile mode, on every
          profile deploy, without a restart): missing players are added and
          anyone else is removed. Names are matched case-insensitively.
        '';
        default = null;
        example = [ "FudoNiten" ];
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
        type = nullOr str;
        description = ''
          Password for the RCON remote console, which the module uses to apply
          gamerules, ops and the whitelist. A literal lands in the
          world-readable store (and in the profile); prefer
          `rcon-password-file`. Exactly one of the two must be set.
        '';
        default = null;
      };

      rcon-password-file = mkOption {
        type = nullOr str;
        description = ''
          File holding the RCON password, read at runtime (an Aegis target,
          for preference). It must be readable by the server user. Add the
          unit that provides it to `secret-units`.
        '';
        default = null;
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
        description =
          "Hours of player inactivity before an on-demand server shuts down.";
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
        enable-rcon = true;
        pvp = serverConf.allow-pvp;
        white-list = serverConf.white-list;
        # spawn-protection is a radius in blocks; 0 disables it entirely.
        spawn-protection = if serverConf.spawn-protection then 16 else 0;
      } // seedAttr // optionalAttrs (serverConf.rcon-password != null) {
        "rcon.password" = serverConf.rcon-password;
      };
    in pkgs.writeText "mc-${sanitizeName name}.properties" (toProps props);


  enabledServers = filterAttrs (_: s: s.enable) cfg.servers;
  onDemandServers = filterAttrs (_: s: s.on-demand) enabledServers;

  boolStr = v: if v then "true" else "false";

  eulaFile = pkgs.writeText "mc-eula.txt" "eula=true";

  # How many 5-second attempts to give RCON to come up after a start.
  rconAttempts = 60;

  # mcrcon reads the password from MCRCON_PASS, which keeps it off the
  # command line (and, with a file, out of the store). Every script that
  # calls rconCmd runs rconAuth first.
  rconCmd = serverConf:
    "${pkgs.mcrcon}/bin/mcrcon -c -H 127.0.0.1 -P ${
      toString serverConf.rcon-port
    }";

  rconAuth = serverConf:
    if serverConf.rcon-password-file != null then
      ''MCRCON_PASS=$(${pkgs.coreutils}/bin/cat ${
        escapeShellArg serverConf.rcon-password-file
      }); export MCRCON_PASS''
    else
      "export MCRCON_PASS=${escapeShellArg serverConf.rcon-password}";

  # server.properties is a store path, so a file-held password is spliced
  # into the copy in the state directory at start.
  appendRconPassword = serverConf: propsPath:
    optionalString (serverConf.rcon-password-file != null) ''
      printf '\nrcon.password=%s\n' "$(cat ${
        escapeShellArg serverConf.rcon-password-file
      })" >> ${propsPath}
    '';

  genStartScript = name: serverConf:
    let
      safeName = sanitizeName name;
      svcName = "minecraft-${safeName}";
      mem = "${toString serverConf.allocated-memory}G";
      flags =
        # Required by JNA (used by OSHI for hardware telemetry). Without
        # this, newer JVMs will block native access entirely.
        [
          "--enable-native-access=ALL-UNNAMED"
          # JNA extracts a native .so to a tmpdir before loading it. The
          # state directory is typically noexec, so we redirect JNA to the
          # service's runtime directory (/run/...) which is always exec.
          "-Djna.tmpdir=/run/${svcName}"
        ] ++ commonFlags ++ [ "-Xms${mem}" "-Xmx${mem}" ]
        ++ optionals (serverConf.allocated-memory >= 12) highMemFlags;
    in pkgs.writeShellScript "mc-start-${safeName}.sh"
    "exec ${serverConf.package}/bin/minecraft-server ${
      concatStringsSep " " flags
    }";

  # Everything that only takes effect on a restart: the jar (through the start
  # script), the JVM flags and server.properties. In profile mode this is what
  # a settings change or a version bump changes, and the system closure
  # doesn't move.
  genRuntime = name: serverConf:
    let safeName = sanitizeName name;
    in pkgs.runCommand "mc-${safeName}-runtime" { } ''
      mkdir -p $out
      ln -s ${genStartScript name serverConf} $out/start
      ln -s ${genPropsFile name serverConf} $out/server.properties
      ln -s ${eulaFile} $out/eula.txt
      printf '%s' ${
        escapeShellArg (serverConf.package.version or "unknown")
      } > $out/version
    '';

  # Applies the settings a running server can take without a restart:
  # gamerules, ops and the whitelist. Waits for RCON first. With --strict
  # (profile deploys) RCON not answering is an error; without it
  # (ExecStartPost) it is a warning, so a slow start doesn't fail the unit.
  genSync = name: serverConf:
    let
      safeName = sanitizeName name;
      rcon = rconCmd serverConf;
      wanted = serverConf.whitelist;
    in pkgs.writeShellScript "mc-sync-${safeName}.sh" ''
      export PATH=${
        makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gnused ]
      }:$PATH

      ${rconAuth serverConf}

      strict=0
      [ "''${1:-}" = "--strict" ] && strict=1

      ready=0
      for attempt in $(seq 1 ${toString rconAttempts}); do
        if ${rcon} "list" >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 5
      done
      if [ $ready = 0 ]; then
        echo "${name}: timed out waiting for RCON; gamerules, ops and whitelist not applied." >&2
        exit $strict
      fi

      ${rcon} "gamerule minecraft:keep_inventory ${
        boolStr serverConf.keep-inventory
      }"
      ${concatMapStrings (op: ''
        ${rcon} ${escapeShellArg "op ${op}"}
      '') serverConf.ops}
      ${optionalString (wanted != null) ''
        wanted=${escapeShellArg (concatStringsSep "\n" wanted)}
        lower() { printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'; }

        # "There are 2 whitelisted player(s): alice, bob", or
        # "There are no whitelisted players".
        if ! listing=$(${rcon} "whitelist list"); then
          echo "${name}: could not read the whitelist." >&2
          exit $strict
        fi
        current=$(printf '%s\n' "$listing" \
          | sed -n 's/^[^:]*: //p' | tr ',' '\n' \
          | sed 's/^ *//; s/ *$//; /^$/d')

        printf '%s\n' "$wanted" | while IFS= read -r player; do
          [ -n "$player" ] || continue
          if ! lower "$current" | grep -qxF "$(lower "$player")"; then
            echo "${name}: adding $player to the whitelist"
            ${rcon} "whitelist add $player"
          fi
        done
        printf '%s\n' "$current" | while IFS= read -r player; do
          [ -n "$player" ] || continue
          if ! lower "$wanted" | grep -qxF "$(lower "$player")"; then
            echo "${name}: removing $player from the whitelist"
            ${rcon} "whitelist remove $player"
          fi
        done
      ''}
      exit 0
    '';

  genAccess = name: serverConf:
    let safeName = sanitizeName name;
    in pkgs.runCommand "mc-${safeName}-access" { } ''
      mkdir -p $out
      ln -s ${genSync name serverConf} $out/sync
    '';

  # Profile activation, run by deploy-rs after it links the profile. Per
  # server: if the running server already uses this runtime, apply the access
  # settings live; otherwise restart it and wait for it to answer. Any failure
  # exits non-zero, so deploy-rs's autoRollback puts the previous profile back
  # and re-runs its activation.
  genActivateServer = name: serverConf:
    let
      safeName = sanitizeName name;
      unit = "minecraft-${safeName}.service";
      runtime = genRuntime name serverConf;
      sync = genSync name serverConf;
      rcon = rconCmd serverConf;
    in ''
      ${rconAuth serverConf}
      want=${runtime}
      have=$(cat /run/minecraft-${safeName}/runtime 2>/dev/null || true)
      if systemctl is-active --quiet ${unit} && [ "$have" = "$want" ]; then
        echo "${name}: server unchanged; applying gamerules, ops and whitelist"
        if ! ${sync} --strict; then
          echo "${name}: could not apply settings" >&2
          status=1
        fi
      ${
        optionalString serverConf.on-demand ''
          elif ! systemctl is-active --quiet ${unit}; then
            echo "${name}: on-demand and stopped; changes apply on its next start"
        ''
      }else
        if systemctl is-active --quiet ${unit} \
           && ${rcon} "say Server restarting for an update. Back in a minute or two." >/dev/null 2>&1; then
          sleep 10
        fi
        echo "${name}: restarting ${unit}"
        healthy=0
        if systemctl restart ${unit}; then
          for attempt in $(seq 1 ${toString rconAttempts}); do
            if systemctl is-active --quiet ${unit} && ${rcon} "list" >/dev/null 2>&1; then
              healthy=1
              break
            fi
            systemctl is-active --quiet ${unit} || break
            sleep 5
          done
        fi
        if [ $healthy = 1 ]; then
          echo "${name}: up and answering RCON"
          have=$(cat /run/minecraft-${safeName}/runtime 2>/dev/null || true)
          if [ "$have" != "$want" ]; then
            echo "${name}: warning: ${unit} is not running from this profile yet; deploy the system profile too." >&2
          fi
        else
          echo "${name}: ${unit} did not come up" >&2
          journalctl --unit ${unit} --lines 30 --no-pager >&2 || true
          status=1
        fi
      fi
    '';

  activateScript = pkgs.writeShellScript "minecraft-profile-activate" ''
    export PATH=/run/current-system/sw/bin:${
      makeBinPath [ pkgs.coreutils ]
    }:$PATH
    status=0
    ${concatStringsSep "\n" (mapAttrsToList genActivateServer enabledServers)}
    exit $status
  '';

  profileBundle = pkgs.runCommand "minecraft-profile" { } ''
    mkdir -p $out/bin
    ${concatStrings (mapAttrsToList (name: serverConf:
      let safeName = sanitizeName name;
      in ''
        mkdir -p $out/${safeName}
        ln -s ${genRuntime name serverConf} $out/${safeName}/runtime
        ln -s ${genAccess name serverConf} $out/${safeName}/access
      '') enabledServers)}
    ln -s ${activateScript} $out/bin/minecraft-profile-activate
  '';

  # Daily health check: each always-on server answers a status ping on its
  # game port, and (optionally) runs Mojang's latest release, since a client
  # that has updated past the server can't join.
  checkScript = pkgs.writeShellScript "minecraft-check.sh" ''
    export PATH=${
      makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
        pkgs.python3Packages.mcstatus
      ]
    }
    status=0
    latest=""
    ${optionalString cfg.check.version-drift ''
      if ! latest=$(curl -fsS --max-time 30 \
          https://piston-meta.mojang.com/mc/game/version_manifest_v2.json \
          | jq -er .latest.release); then
        echo "Could not read Mojang's version manifest."
        latest=""
        status=1
      fi
    ''}
    ${concatStringsSep "\n" (mapAttrsToList (name: serverConf:
      let
        safeName = sanitizeName name;
        port = toString serverConf.port;
        versionExpr = if cfg.profile.enable then
          "$(cat ${cfg.profile.path}/${safeName}/runtime/version 2>/dev/null || echo unknown)"
        else
          escapeShellArg (serverConf.package.version or "unknown");
      in ''
        version=${versionExpr}
        ${optionalString (!serverConf.on-demand) ''
          json=$(mcstatus 127.0.0.1:${port} json)
          if [ "$(printf '%s' "$json" | jq -r .online)" = true ]; then
            echo "${name}: up on port ${port}, version $(printf '%s' "$json" | jq -r '.status.version.name'), $(printf '%s' "$json" | jq -r '.status.players.online')/$(printf '%s' "$json" | jq -r '.status.players.max') players"
          else
            echo "${name}: not answering on port ${port}: $(printf '%s' "$json" | jq -r '.error // "unknown error"')"
            status=1
          fi
        ''}
        if [ -n "$latest" ] && [ "$version" != "$latest" ]; then
          echo "${name}: runs $version, but Mojang's latest release is $latest. Bump it before clients update."
          status=1
        fi
      '') enabledServers)}
    exit $status
  '';

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

    secret-units = mkOption {
      type = listOf str;
      description = ''
        Units that provide secrets the servers read, such as the Aegis
        decrypt unit behind `rcon-password-file`. Every server unit starts
        after them and wants them. Deliberately not `requires`: a restart
        of a required unit restarts its dependents, and an Aegis profile
        deploy restarts every decrypt unit on the host, which would kick
        players off for an unrelated secret rotation. The flip side is that
        rotating the RCON password itself needs a server restart.
      '';
      default = [ ];
      example = [ "aegis-secret-minecraft-rcon-password.service" ];
    };

    servers = mkOption {
      type = attrsOf (submodule serverOpts);
      description = "Minecraft server instances to run.";
      default = { };
    };

    profile = {
      enable = mkOption {
        type = bool;
        description = ''
          Run the servers from a standalone profile at `profile.path` rather
          than from the system closure, so a version bump or a settings change
          deploys on its own (with deploy-rs, as a profile whose path is
          `profile.package` and whose activation runs
          `bin/minecraft-profile-activate` from it) instead of as a system
          deploy.

          The system keeps the user, firewall, ports, RCON password and the
          units, which read everything else through the profile link, so
          changing the rest never changes the system closure. The servers
          refuse to start until the profile exists.
        '';
        default = false;
      };

      path = mkOption {
        type = str;
        description = "Profile the servers read their runtime from.";
        default = "/nix/var/nix/profiles/minecraft";
      };

      package = mkOption {
        type = package;
        readOnly = true;
        description = ''
          The profile's contents: per server, `<name>/runtime` (start script,
          server.properties, eula.txt, version) and `<name>/access` (the
          gamerule/op/whitelist sync), plus `bin/minecraft-profile-activate`,
          which applies the access settings live when the runtime is
          unchanged, restarts the server otherwise, and fails if it doesn't
          come back.
        '';
      };
    };

    check = {
      enable = mkEnableOption
        "a periodic check that each server answers and runs Mojang's latest release";

      calendar = mkOption {
        type = str;
        description = "When to run the check (systemd OnCalendar).";
        default = "daily";
      };

      version-drift = mkOption {
        type = bool;
        description = ''
          Fail the check when a server's version isn't Mojang's latest
          release: clients update themselves, and one that has updated past
          the server can't join.
        '';
        default = true;
      };

      on-failure = mkOption {
        type = listOf str;
        description =
          "Units to start when the check fails (e.g. a notifier).";
        default = [ ];
        example = [ "fudo-notify@%n.service" ];
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = mapAttrsToList (name: serverConf: {
      assertion = (serverConf.rcon-password == null)
        != (serverConf.rcon-password-file == null);
      message =
        "fudo.services.minecraft.server.servers.${name} needs exactly one of rcon-password or rcon-password-file.";
    }) cfg.servers;

    fudo.services.minecraft.server.profile.package = profileBundle;

    users = {
      users."${cfg.user}" = {
        isSystemUser = true;
        home = cfg.state-directory;
        group = cfg.group;
        createHome = true;
      };
      groups."${cfg.group}" = { members = [ cfg.user ]; };
    };

    # Game port: TCP, open to everyone.
    networking.firewall.allowedTCPPorts =
      map (s: s.port) (filter (s: s.enable) (attrValues cfg.servers));

    # Query port: UDP (GS4 protocol), open to everyone — read-only server status.
    networking.firewall.allowedUDPPorts =
      map (s: s.query-port) (filter (s: s.enable) (attrValues cfg.servers));

    # RCON port: TCP, Tailscale interface only. The RCON protocol has no
    # encryption so it must not be exposed on public interfaces. Restricting to
    # tailscale0 works regardless of the node's Tailscale IP; the rule is a
    # no-op on machines without Tailscale.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts =
      map (s: s.rcon-port) (filter (s: s.enable) (attrValues cfg.servers));

    systemd = let

      genMainService = name: serverConf:
        let
          safeName = sanitizeName name;
          svcName = "minecraft-${safeName}";
          stateDir = serverStateDir name;
          runDir = "/run/${svcName}";
          profileServer = "${cfg.profile.path}/${safeName}";

          propsFile = genPropsFile name serverConf;

          onDemandStamp = optionalString serverConf.on-demand
            "date +%s > ${stateDir}/.last-player-time";

          preStartScript = pkgs.writeShellScript "mc-init-${safeName}.sh" ''
            cp -f ${propsFile} ${stateDir}/server.properties
            cp -f ${eulaFile} ${stateDir}/eula.txt
            chmod 0600 ${stateDir}/server.properties
            ${appendRconPassword serverConf "${stateDir}/server.properties"}
            ${onDemandStamp}
          '';

          # Profile mode: resolve the profile once, and record what this start
          # used so ExecStart and the deploy-time activation agree on it.
          profilePreStartScript =
            pkgs.writeShellScript "mc-init-${safeName}.sh" ''
              if ! runtime=$(readlink -e ${profileServer}/runtime); then
                echo "${name}: nothing at ${profileServer}/runtime; deploy the Minecraft profile." >&2
                exit 1
              fi
              cp -f "$runtime/server.properties" ${stateDir}/server.properties
              cp -f "$runtime/eula.txt" ${stateDir}/eula.txt
              chmod u+w ${stateDir}/eula.txt
              chmod 0600 ${stateDir}/server.properties
              ${appendRconPassword serverConf "${stateDir}/server.properties"}
              printf '%s\n' "$runtime" > ${runDir}/runtime
              ${onDemandStamp}
            '';

          profileStartScript =
            pkgs.writeShellScript "mc-start-${safeName}.sh" ''
              exec "$(cat ${runDir}/runtime)/start"
            '';

        in nameValuePair svcName {
          description = "${name} Minecraft Server";
          wantedBy = optionals (!serverConf.on-demand) [ "multi-user.target" ];
          # Start the idle-check timer alongside this service (on-demand
          # only), and pull in the secret units.
          after = [ "network-online.target" ] ++ cfg.secret-units;
          requires = [ "network-online.target" ];
          wants = optionals serverConf.on-demand
            [ "${svcName}-idle-check.timer" ] ++ cfg.secret-units;
          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = stateDir;
            # Polls until RCON is ready, then syncs gamerules, ops and the
            # whitelist declared in config.
            ExecStartPost = if cfg.profile.enable then
              "${profileServer}/access/sync"
            else
              "${genSync name serverConf}";
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
          } // (if cfg.profile.enable then {
            ExecStartPre = "${profilePreStartScript}";
            ExecStart = "${profileStartScript}";
            # ExecStartPost waits up to five minutes for RCON, and a deploy
            # restart waits on the whole start.
            TimeoutStartSec = 600;
          } else {
            ExecStartPre = "${preStartScript}";
            ExecStart = "${genStartScript name serverConf}";
          });
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

          waitForRconScript =
            pkgs.writeShellScript "mc-wait-rcon-${safeName}.sh" ''
              ${rconAuth serverConf}
              for attempt in $(seq 1 120); do
                if ${pkgs.mcrcon}/bin/mcrcon \
                    -H 127.0.0.1 \
                    -P ${toString serverConf.rcon-port} \
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
            ExecStart =
              "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${internalPort}";
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

          idleCheckScript =
            pkgs.writeShellScript "mc-idle-check-${safeName}.sh" ''
              ${rconAuth serverConf}
              LAST_PLAYER_FILE="${stateDir}/.last-player-time"
              IDLE_TIMEOUT=${idleTimeoutSecs}

              if ! systemctl is-active --quiet "${svcName}.service"; then
                exit 0
              fi

              PLAYER_LIST=$(${pkgs.mcrcon}/bin/mcrcon \
                -H 127.0.0.1 \
                -P ${toString serverConf.rcon-port} \
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
      tmpfiles.rules = mapAttrsToList
        (name: _: "d ${serverStateDir name} 0700 ${cfg.user} ${cfg.group} - -")
        enabledServers;

      services = (mapAttrs' genMainService enabledServers)
        // (mapAttrs' genProxyService onDemandServers)
        // (mapAttrs' genIdleCheckService onDemandServers)
        // optionalAttrs cfg.check.enable {
          minecraft-check = {
            description = "Check the Minecraft servers answer and are current";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            onFailure = cfg.check.on-failure;
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${checkScript}";
              DynamicUser = true;
            };
          };
        };

      sockets = mapAttrs' genProxySocket onDemandServers;

      timers = mapAttrs' genIdleCheckTimer onDemandServers
        // optionalAttrs cfg.check.enable {
          minecraft-check = {
            description = "Daily Minecraft server check";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = cfg.check.calendar;
              Persistent = true;
              RandomizedDelaySec = "15min";
            };
          };
        };
    };
  };
}
