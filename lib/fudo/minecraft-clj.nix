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

in {
  options.fudo.minecraft-clj = with types; {
    enable = mkEnableOption "Enable Minecraft server with Clojure repl.";

    data-dir = mkOption {
      type = str;
      description = "Path at which to store Minecraft data.";
    };

    allocated-memory = mkOption {
      type = int;
      description = "Memory to allocate to Minecraft, in GB.";
      default = 4;
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
  };

  config = {
    users = {
      users."${cfg.user}" = {
        isSystemUser = false;
        home = cfg.data-dir;
        group = cfg.group;
        createHome = true;
      };
      groups."${cfg.group}" = { members = [ cfg.user ]; };
    };

    systemd.services.minecraft-clj = {
      description = "Minecraft server with Clojure REPL.";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart = let
          mem = "${cfg.allocated-memory}G";
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
        MemoryDenyWriteExecute = true;
      };
    };
  };
}
