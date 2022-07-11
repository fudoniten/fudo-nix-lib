{ pkgs, lib, config, ... }:

with lib;
let
  cfg = config.fudo.system;

  mkDisableOption = description:
    mkOption {
      type = types.bool;
      default = true;
      description = description;
    };

  isEmpty = lst: 0 == (length lst);

  serviceOpts = { name, ... }:
    with types; {
      options = {
        after = mkOption {
          type = listOf str;
          description = "List of services to start before this one.";
          default = [ ];
        };
        script = mkOption {
          type = nullOr str;
          description = "Simple shell script for the service to run.";
          default = null;
        };
        reloadScript = mkOption {
          type = nullOr str;
          description = "Script to run whenever the service is restarted.";
          default = null;
        };
        before = mkOption {
          type = listOf str;
          description =
            "List of services before which this service should be started.";
          default = [ ];
        };
        requires = mkOption {
          type = listOf str;
          description =
            "List of services on which this service depends. If they fail to start, this service won't start.";
          default = [ ];
        };
        preStart = mkOption {
          type = nullOr str;
          description = "Script to run prior to starting this service.";
          default = null;
        };
        postStart = mkOption {
          type = nullOr str;
          description = "Script to run after starting this service.";
          default = null;
        };
        preStop = mkOption {
          type = nullOr str;
          description = "Script to run prior to stopping this service.";
          default = null;
        };
        postStop = mkOption {
          type = nullOr str;
          description = "Script to run after stopping this service.";
          default = null;
        };
        requiredBy = mkOption {
          type = listOf str;
          description =
            "List of services which require this service, and should fail without it.";
          default = [ ];
        };
        wantedBy = mkOption {
          type = listOf str;
          default = [ ];
          description =
            "List of services before which this service should be started.";
        };
        environment = mkOption {
          type = attrsOf str;
          description = "Environment variables supplied to this service.";
          default = { };
        };
        environmentFile = mkOption {
          type = nullOr str;
          description =
            "File containing environment variables supplied to this service.";
          default = null;
        };
        description = mkOption {
          type = str;
          description = "Description of the service.";
        };
        path = mkOption {
          type = listOf package;
          description =
            "A list of packages which should be in the service PATH.";
          default = [ ];
        };
        restartIfChanged =
          mkDisableOption "Restart the service if the definition changes.";
        dynamicUser = mkDisableOption "Create a new user for this service.";
        privateNetwork = mkDisableOption "Only allow access to localhost.";
        privateUsers =
          mkDisableOption "Don't allow access to system user list.";
        privateDevices = mkDisableOption
          "Restrict access to system devices other than basics.";
        privateTmp = mkDisableOption "Limit service to a private tmp dir.";
        protectControlGroups =
          mkDisableOption "Don't allow service to modify control groups.";
        protectClock =
          mkDisableOption "Don't allow service to modify system clock.";
        restrictSuidSgid =
          mkDisableOption "Don't allow service to suid or sgid binaries.";
        protectKernelTunables =
          mkDisableOption "Don't allow service to modify kernel tunables.";
        privateMounts =
          mkDisableOption "Don't allow service to access mounted devices.";
        protectKernelModules = mkDisableOption
          "Don't allow service to load or evict kernel modules.";
        protectHome = mkDisableOption "Limit access to home directories.";
        protectHostname =
          mkDisableOption "Don't allow service to modify hostname.";
        protectKernelLogs =
          mkDisableOption "Don't allow access to kernel logs.";
        lockPersonality = mkDisableOption "Lock service 'personality'.";
        restrictRealtime =
          mkDisableOption "Restrict service from using realtime functionality.";
        restrictNamespaces =
          mkDisableOption "Restrict service from using namespaces.";
        memoryDenyWriteExecute = mkDisableOption
          "Restrict process from executing from writable memory.";
        keyringMode = mkOption {
          type = str;
          default = "private";
          description = "Sharing state of process keyring.";
        };
        requiredCapabilities = mkOption {
          type = listOf (enum capabilities);
          default = [ ];
          description = "List of capabilities granted to the service.";
        };
        restartWhen = mkOption {
          type = str;
          default = "on-failure";
          description = "Conditions under which process should be restarted.";
        };
        restartSec = mkOption {
          type = int;
          default = 10;
          description = "Number of seconds to wait before restarting service.";
        };
        execStart = mkOption {
          type = nullOr str;
          default = null;
          description = "Command to run to launch the service.";
        };
        execStop = mkOption {
          type = nullOr str;
          default = null;
          description = "Command to run to launch the service.";
        };
        protectSystem = mkOption {
          type = enum [ "true" "false" "full" "strict" true false ];
          default = "full";
          description =
            "Level of protection to apply to the system for this service.";
        };
        addressFamilies = mkOption {
          type = nullOr (listOf (enum address-families));
          default = [ ];
          description = "List of address families which the service can use.";
        };
        workingDirectory = mkOption {
          type = nullOr path;
          default = null;
          description = "Directory in which to launch the service.";
        };
        user = mkOption {
          type = nullOr str;
          default = null;
          description = "User as which to launch this service.";
        };
        group = mkOption {
          type = nullOr str;
          default = null;
          description = "Primary group as which to launch this service.";
        };
        type = mkOption {
          type =
            enum [ "simple" "exec" "forking" "oneshot" "dbus" "notify" "idle" ];
          default = "simple";
          description = "Systemd service type of this service.";
        };
        partOf = mkOption {
          type = listOf str;
          default = [ ];
          description =
            "List of targets to which this service belongs (and with which it should be restarted).";
        };
        standardOutput = mkOption {
          type = str;
          default = "journal";
          description = "Destination of standard output for this service.";
        };
        standardError = mkOption {
          type = str;
          default = "journal";
          description = "Destination of standard error for this service.";
        };
        pidFile = mkOption {
          type = nullOr str;
          default = null;
          description = "Service PID file.";
        };
        networkWhitelist = mkOption {
          type = nullOr (listOf str);
          default = null;
          description =
            "A list of networks with which this process may communicate.";
        };
        allowedSyscalls = mkOption {
          type = listOf (enum syscalls);
          default = [ ];
          description = "System calls which the service is permitted to make.";
        };
        maximumUmask = mkOption {
          type = str;
          default = "0077";
          description = "Umask to apply to files created by the service.";
        };
        startOnlyPerms = mkDisableOption "Disable perms after startup.";
        onCalendar = mkOption {
          type = nullOr str;
          description =
            "Schedule on which the job should be invoked. See: man systemd.time(7).";
          default = null;
        };
        runtimeDirectory = mkOption {
          type = nullOr str;
          description =
            "Directory created at runtime with perms for the service to read/write.";
          default = null;
        };
        readWritePaths = mkOption {
          type = listOf str;
          description =
            "A list of paths to which the service will be allowed normal access, even if ProtectSystem=strict.";
          default = [ ];
        };
        stateDirectory = mkOption {
          type = nullOr str;
          description =
            "State directory for the service, available via STATE_DIRECTORY.";
          default = null;
        };
        cacheDirectory = mkOption {
          type = nullOr str;
          description =
            "Cache directory for the service, available via CACHE_DIRECTORY.";
          default = null;
        };
        inaccessiblePaths = mkOption {
          type = listOf str;
          description =
            "A list of paths which should be inaccessible to the service.";
          default = [ "/home" "/root" ];
        };
        # noExecPaths = mkOption {
        #   type = listOf str;
        #   description =
        #     "A list of paths where the service will not be allowed to run executables.";
        #   default = [ "/home" "/root" "/tmp" "/var" ];
        # };
        readOnlyPaths = mkOption {
          type = listOf str;
          description =
            "A list of paths to which will be read-only for the service.";
          default = [ ];
        };
        execPaths = mkOption {
          type = listOf str;
          description =
            "A list of paths where the service WILL be allowed to run executables.";
          default = [ ];
        };
      };
    };

  # See: man capabilities(7)
  capabilities = [
    "CAP_AUDIT_CONTROL"
    "CAP_AUDIT_READ"
    "CAP_AUDIT_WRITE"
    "CAP_BLOCK_SUSPEND"
    "CAP_BPF"
    "CAP_CHECKPOINT_RESTORE"
    "CAP_CHOWN"
    "CAP_DAC_OVERRIDE"
    "CAP_DAC_READ_SEARCH"
    "CAP_FOWNER"
    "CAP_FSETID"
    "CAP_IPC_LOCK"
    "CAP_IPC_OWNER"
    "CAP_KILL"
    "CAP_LEASE"
    "CAP_LINUX_IMMUTABLE"
    "CAP_MAC_ADMIN"
    "CAP_MAC_OVERRIDE"
    "CAP_MKNOD"
    "CAP_NET_ADMIN"
    "CAP_NET_BIND_SERVICE"
    "CAP_NET_BROADCAST"
    "CAP_NET_RAW"
    "CAP_PERFMON"
    "CAP_SETGID"
    "CAP_SETFCAP"
    "CAP_SETPCAP"
    "CAP_SETUID"
    "CAP_SYS_ADMIN"
    "CAP_SYS_BOOT"
    "CAP_SYS_CHROOT"
    "CAP_SYS_MODULE"
    "CAP_SYS_NICE"
    "CAP_SYS_PACCT"
    "CAP_SYS_PTRACE"
    "CAP_SYS_RAWIO"
    "CAP_SYS_RESOURCE"
    "CAP_SYS_TIME"
    "CAP_SYS_TTY_CONFIG"
    "CAP_SYSLOG"
    "CAP_WAKE_ALARM"
  ];

  syscalls = [
    "@clock"
    "@debug"
    "@module"
    "@mount"
    "@raw-io"
    "@reboot"
    "@swap"
    "@privileged"
    "@resources"
    "@cpu-emulation"
    "@obsolete"
  ];

  address-families = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

  restrict-capabilities = allowed:
    if (allowed == [ ]) then
      "~${concatStringsSep " " capabilities}"
    else
      concatStringsSep " " allowed;

  restrict-syscalls = allowed:
    if (allowed == [ ]) then
      "~${concatStringsSep " " syscalls}"
    else
      concatStringsSep " " allowed;

  restrict-address-families = allowed:
    if (allowed == [ ]) then [ "~AF_INET" "~AF_INET6" ] else allowed;

in {
  options.fudo.system = with types; {
    services = mkOption {
      type = attrsOf (submodule serviceOpts);
      description = "Fudo system service definitions, with secure defaults.";
      default = { };
    };

    tmpOnTmpfs = mkOption {
      type = bool;
      description = "Put tmp filesystem on tmpfs (needs enough RAM).";
      default = true;
    };
  };

  config = {

    systemd.timers = mapAttrs (name: opts: {
      enable = true;
      description = opts.description;
      partOf = [ "${name}.timer" ];
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = opts.onCalendar; };
    }) (filterAttrs (name: opts: opts.onCalendar != null) cfg.services);

    systemd.targets.fudo-init = { wantedBy = [ "multi-user.target" ]; };

    systemd.services = mapAttrs (name: opts: {
      enable = true;
      script = mkIf (opts.script != null) opts.script;
      reload = mkIf (opts.reloadScript != null) opts.reloadScript;
      after = opts.after ++ [ "fudo-init.target" ];
      before = opts.before;
      requires = opts.requires;
      wantedBy = opts.wantedBy;
      preStart = mkIf (opts.preStart != null) opts.preStart;
      postStart = mkIf (opts.postStart != null) opts.postStart;
      postStop = mkIf (opts.postStop != null) opts.postStop;
      preStop = mkIf (opts.preStop != null) opts.preStop;
      partOf = opts.partOf;
      requiredBy = opts.requiredBy;
      environment = opts.environment;
      description = opts.description;
      restartIfChanged = opts.restartIfChanged;
      path = opts.path;
      serviceConfig = {
        PrivateNetwork = opts.privateNetwork;
        PrivateUsers = mkIf (opts.user == null) opts.privateUsers;
        PrivateDevices = opts.privateDevices;
        PrivateTmp = opts.privateTmp;
        PrivateMounts = opts.privateMounts;
        ProtectControlGroups = opts.protectControlGroups;
        ProtectKernelTunables = opts.protectKernelTunables;
        ProtectKernelModules = opts.protectKernelModules;
        ProtectSystem = opts.protectSystem;
        ProtectHostname = opts.protectHostname;
        ProtectHome = opts.protectHome;
        ProtectClock = opts.protectClock;
        ProtectKernelLogs = opts.protectKernelLogs;
        KeyringMode = opts.keyringMode;
        EnvironmentFile =
          mkIf (opts.environmentFile != null) opts.environmentFile;

        # This  is more complicated than it looks...
        # CapabilityBoundingSet = restrict-capabilities opts.requiredCapabilities;
        AmbientCapabilities = concatStringsSep " " opts.requiredCapabilities;
        SecureBits = mkIf ((length opts.requiredCapabilities) > 0) "keep-caps";

        DynamicUser = mkIf (opts.user == null) opts.dynamicUser;

        Restart = opts.restartWhen;
        WorkingDirectory =
          mkIf (opts.workingDirectory != null) opts.workingDirectory;
        RestrictAddressFamilies = optionals (opts.addressFamilies != null)
          (restrict-address-families opts.addressFamilies);
        RestrictNamespaces = opts.restrictNamespaces;
        User = mkIf (opts.user != null) opts.user;
        Group = mkIf (opts.group != null) opts.group;
        Type = opts.type;
        StandardOutput = opts.standardOutput;
        PIDFile = mkIf (opts.pidFile != null) opts.pidFile;
        LockPersonality = opts.lockPersonality;
        RestrictRealtime = opts.restrictRealtime;
        ExecStart = mkIf (opts.execStart != null) opts.execStart;
        ExecStop = mkIf (opts.execStop != null) opts.execStop;
        MemoryDenyWriteExecute = opts.memoryDenyWriteExecute;
        SystemCallFilter = restrict-syscalls opts.allowedSyscalls;
        UMask = opts.maximumUmask;
        IpAddressAllow =
          mkIf (opts.networkWhitelist != null) opts.networkWhitelist;
        IpAddressDeny = mkIf (opts.networkWhitelist != null) "any";
        LimitNOFILE = "49152";
        PermissionsStartOnly = opts.startOnlyPerms;
        RuntimeDirectory =
          mkIf (opts.runtimeDirectory != null) opts.runtimeDirectory;
        CacheDirectory = mkIf (opts.cacheDirectory != null) opts.cacheDirectory;
        StateDirectory = mkIf (opts.stateDirectory != null) opts.stateDirectory;
        ReadWritePaths = opts.readWritePaths;
        ReadOnlyPaths = opts.readOnlyPaths;
        InaccessiblePaths = opts.inaccessiblePaths;
        # Apparently not supported yet?
        # NoExecPaths = opts.noExecPaths;
        ExecPaths = opts.execPaths;
      };
    }) config.fudo.system.services;
  };
}
