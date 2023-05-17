{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.fudo.client.dns;

  hostname = config.instance.hostname;

in {
  options.fudo.client.dns = {
    enable = mkEnableOption "Enable Backplane DNS client.";

    ipv4 = mkOption {
      type = types.bool;
      default = true;
      description = "Report host external IPv4 address to Fudo DynDNS server.";
    };

    ipv6 = mkOption {
      type = types.bool;
      default = true;
      description = "Report host external IPv6 address to Fudo DynDNS server.";
    };

    sshfp = mkOption {
      type = types.bool;
      default = true;
      description = "Report host SSH fingerprints to the Fudo DynDNS server.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain under which this host is registered.";
    };

    server = mkOption {
      type = types.str;
      description = "Backplane DNS server to which changes will be reported.";
      default = "backplane.fudo.org";
    };

    password-file = mkOption {
      type = types.str;
      description = "File containing host password for backplane.";
      example = "/path/to/secret.passwd";
    };

    frequency = mkOption {
      type = types.str;
      description =
        "Frequency at which to report the local IP(s) to backplane.";
      default = "*:0/15";
    };

    user = mkOption {
      type = types.str;
      description =
        "User as which to run the client script (must have access to password file).";
      default = "backplane-dns-client";
    };

    external-interface = mkOption {
      type = with types; nullOr str;
      description =
        "Interface with which this host communicates with the larger internet.";
      default = null;
    };
  };

  config = mkIf cfg.enable {

    users = {
      users = {
        "${cfg.user}" = {
          isSystemUser = true;
          createHome = true;
          home = "/run/home/${cfg.user}";
          group = cfg.user;
        };
      };

      groups = { "${cfg.user}" = { members = [ cfg.user ]; }; };
    };

    systemd = {
      tmpfiles.rules = [
        "d /run/home 755 root - - -"
        "d /run/home/${cfg.user} 700 ${cfg.user} - - -"
      ];

      timers.backplane-dns-client = {
        enable = true;
        description = "Report local IP addresses to Fudo backplane.";
        partOf = [ "backplane-dns-client.service" ];
        wantedBy = [ "timers.target" ];
        requires = [ "network-online.target" ];
        timerConfig = { OnCalendar = cfg.frequency; };
      };

      services = let sshfp-file = "/tmp/${hostname}-sshfp/fingerprints";
      in {
        backplane-dns-client-pw-file = {
          requiredBy = [ "backplane-dns-client.service" ];
          reloadIfChanged = true;
          serviceConfig = { Type = "oneshot"; };
          script = ''
            chmod 400 ${cfg.password-file}
            chown ${cfg.user} ${cfg.password-file}
          '';
        };

        backplane-dns-generate-sshfps = mkIf cfg.sshfp {
          requiredBy = [ "backplane-dns-client.service" ];
          before = [ "backplane-dns-client.service" ];
          path = with pkgs; [ coreutils openssh ];
          serviceConfig = {
            Type = "oneshot";
            PrivateDevices = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            ProtectClock = true;
            ProtectHome = true;
            ProtectKernelLogs = true;
            #ProtectSystem = true;
            #LockPersonality = true;
            #PermissionsStartOnly = true;
            MemoryDenyWriteExecute = true;
            RestrictRealtime = true;
            LimitNOFILE = 1024;
            ReadWritePaths = [ (dirOf sshfp-file) ];
          };
          script = let
            keyPaths = map (key: key.path) config.services.openssh.hostKeys;
            keyGenCmds = map (path:
              ''
                ssh-keygen -r hostname -f "${path}" | sed 's/hostname IN SSHFP '// >> ${sshfp-file}'')
              keyPaths;
          in ''
            [ -f ${sshfp-file} ] && rm -f ${sshfp-file}
            SSHFP_DIR=$(dirname ${sshfp-file})
            [ -d $SSHFP_DIR ] || mkdir $SSHFP_DIR
            chown ${cfg.user} $SSHFP_DIR
            chmod go-rwx $SSHFP_DIR
            ${concatStringsSep "\n" keyGenCmds}
            chown ${cfg.user} ${sshfp-file}
            chmod 600 ${sshfp-file}
          '';
        };

        backplane-dns-client = {
          enable = true;
          path = with pkgs; [ coreutils ];
          serviceConfig = {
            Type = "oneshot";
            StandardOutput = "journal";
            User = cfg.user;
            ExecStart = pkgs.writeShellScript "start-backplane-dns-client.sh" ''
              SSHFP_ARGS=""
              ${optionalString cfg.sshfp ''
                while read LINE; do SSHFP_ARGS="$SSHFP_ARGS --ssh-fp=\"$LINE\""; done < ${sshfp-file}
              ''}
              CMD="${pkgs.backplaneDnsClient}/bin/backplane-dns-client ${
                optionalString cfg.ipv4 "-4"
              } ${optionalString cfg.ipv6 "-6"} ${
                optionalString cfg.sshfp "$SSHFP_ARGS"
              } ${
                optionalString (cfg.external-interface != null)
                "--interface=${cfg.external-interface}"
              } --domain=${cfg.domain} --server=${cfg.server} --password-file=${cfg.password-file}"
              echo $CMD
              $CMD
            '';
            ExecStartPost = mkIf cfg.sshfp "rm ${sshfp-file}";
            PrivateDevices = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            ProtectClock = true;
            ProtectHome = true;
            ProtectKernelLogs = true;
            MemoryDenyWriteExecute = true;
            ProtectSystem = true;
            LockPersonality = true;
            PermissionsStartOnly = true;
            RestrictRealtime = true;
            ReadOnlyPaths = [ sshfp-file ];
            LimitNOFILE = 1024;
          };
          reloadIfChanged = true;
        };
      };
    };
  };
}
