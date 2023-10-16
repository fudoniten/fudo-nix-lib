{ config, pkgs, lib, ... }@toplevel:

with lib;
let

  hostname = cfg.instance.hostname;

  ifAddrs = ifInfo:
    let addrOnly = addrInfo: addrInfo.address;
    in (map addrOnly (trace ifInfo.ipv4 ifInfo.ipv4).addresses)
    ++ (map addrOnly ifInfo.ipv6.addresses);

  primaryConfig = { config, lib, pkgs, ... }:
    let
      cfg = config.fudo.auth.kerberos;
      hasSecondary = cfg.kdc.primary.secondary-servers != [ ];
      aclFile = let
        aclEntryToString = _:
          { principal, perms, target, ... }:
          let
          in "${principal} ${concatStringsSep "," perms}${
            optionalString (target != null) " ${target}"
          }";
      in pkgs.writeText "kdc.acl" (concatStringsSep "\n"
        (mapAttrsToList aclEntryToString cfg.kdc.primary.acl));

      kdcConf = pkgs.writeText "kdc.conf" ''
        [kdc]
          database = {
            realm = ${cfg.realm}
            dbname = sqlite:${cfg.kdc.database}
            mkey_file = ${cfg.kdc.master-key-file}
            acl_file = ${aclFile}
            log_file = /dev/null
          }

        [realms]
          ${cfg.realm} = {
            enable-http = false;
          }

        [libdefaults]
          default_realm = ${cfg.realm}
          allow_weak_crypto = false

        [logging]
          kdc = FILE:${cfg.kdc.state-directory}/kerberos.log
          default = FILE:${cfg.kdc.state-directory}/kerberos.log
      '';

      kadminLocal = pkgs.writeShellApplication {
        name = "kadmin.local";
        runtimeInputs = with pkgs; [ heimdal ];
        text = ''kadmin --local --config-file=${kdcConf} -- "$@"'';
      };

    in {
      config = mkIf cfg.kdc.primary.enable {

        users = {
          users."${cfg.user}" = {
            isSystemUser = true;
            group = cfg.group;
          };
          groups."${cfg.group}" = { members = [ cfg.user ]; };
        };

        environment.systemPackages = [ kadminLocal ];

        systemd = {
          tmpfiles.rules =
            [ "f ${cfg.kdc.database} 0700 ${cfg.user} ${cfg.group} - -" ];

          services = {
            heimdal-kdc = {
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              description =
                "Heimdal Kerberos Key Distribution Center (primary ticket server).";
              path = with pkgs; [ heimdal ];
              serviceConfig = {
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectControlGroups = true;
                ProtectKernelTunables = true;
                ProtectHostname = true;

                ProtectClock = true;
                ProtectKernelLogs = true;
                MemoryDenyWriteExecute = true;
                RestrictRealtime = true;
                PermissionsStartOnly = false;
                LimitNOFILE = 4096;
                User = cfg.user;
                Group = cfg.group;
                Restart = "always";
                RestartSec = "5s";
                AmbientCapabilities = "CAP_NET_BIND_SERVICE";
                SecureBits = "keep-caps";
                ExecStartPre = let
                  chownScript = ''
                    ${pkgs.coreutils}/bin/chown ${cfg.user}:${cfg.group} ${cfg.kdc.database}
                    ${pkgs.coreutils}/bin/chown ${cfg.user}:${cfg.group} ${cfg.kdc.state-directory}/kerberos.log
                  '';
                in "+${chownScript}";
                ExecStart = let
                  ips = if (cfg.kdc.bind-addresses != [ ]) then
                    cfg.kdc.bind-addresses
                  else
                    [ "0.0.0.0" ];
                  bindClause = "--addresses=${concatStringsSep "," ips}";
                in "${pkgs.heimdal}/libexec/heimdal/kdc --config-file=${kdcConf} --ports=88 ${bindClause}";
              };
            };

            heimdal-kadmind = {
              wantedBy = [ "heimdal-kdc.service" ];
              after = [ "heimdal-kdc.service" ];
              description = "Heimdal Kerberos Administration Server.";
              path = with pkgs; [ heimdal ];
              serviceConfig = {
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectControlGroups = true;
                ProtectKernelTunables = true;
                ProtectHostname = true;
                ProtectClock = true;
                ProtectKernelLogs = true;
                MemoryDenyWriteExecute = true;
                RestrictRealtime = true;
                LimitNOFILE = 4096;
                User = cfg.user;
                Group = cfg.group;
                Restart = "always";
                RestartSec = "5s";
                AmbientCapabilities = "CAP_NET_BIND_SERVICE";
                SecureBits = "keep-caps";
                ExecStart = concatStringsSep " " [
                  "${pkgs.heimdal}/libexec/heimdal/kadmind"
                  "--config-file=${kdcConf}"
                  "--keytab=${cfg.kdc.primary.keytabs.kadmind}"
                  "--realm=${cfg.realm}"
                ];
              };
            };

            heimdal-kpasswdd = {
              wantedBy = [ "heimdal-kdc.service" ];
              after = [ "heimdal-kdc.service" ];
              description = "Heimdal Kerberos Password Server.";
              path = with pkgs; [ heimdal ];
              serviceConfig = {
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectControlGroups = true;
                ProtectKernelTunables = true;
                ProtectSystem = true;
                ProtectHostname = true;
                ProtectHome = true;
                ProtectClock = true;
                ProtectKernelLogs = true;
                MemoryDenyWriteExecute = true;
                RestrictRealtime = true;
                LockPersonality = true;
                PermissionsStartOnly = true;
                LimitNOFILE = 4096;
                User = cfg.user;
                Group = cfg.group;
                Restart = "always";
                RestartSec = "5s";
                AmbientCapabilities = "CAP_NET_BIND_SERVICE";
                SecureBits = "keep-caps";
                ExecStart = concatStringsSep " " [
                  "${pkgs.heimdal}/libexec/heimdal/kpasswdd"
                  "--config-file=${kdcConf}"
                  "--keytab=${cfg.kdc.primary.keytabs.kpasswdd}"
                  "--realm=${cfg.realm}"
                ];
              };
            };

            heimdal-hprop = mkIf hasSecondary {
              wantedBy = [ "heimdal-kdc.service" ];
              after = [ "heimdal-kdc.service" ];
              description =
                "Service to propagate the KDC database to secondary servers.";
              path = with pkgs; [ heimdal ];
              serviceConfig = let staging-db = "$RUNTIME_DIRECTORY/realm.db";
              in {
                User = cfg.user;
                Group = cfg.group;
                Type = "oneshot";
                RuntimeDirectory = "heimdal-hprop";
                ExecStartPre = pkgs.writeShellScript "kdc-prepare-hprop-dump.sh"
                  (concatStringsSep " " [
                    "${pkgs.heimdal}/bin/kadmin"
                    "--local"
                    "--config-file=${kdcConf}"
                    "--"
                    "dump"
                    "--format=Heimdal"
                    "${staging-db}"
                  ]);

                ExecStart = pkgs.writeShellScript "kdc-hprop.sh"
                  (concatStringsSep " " ([
                    "${pkgs.heimdal}/libexec/heimdal/hprop"
                    ''--master-key="${cfg.kdc.master-key-file}"''
                    #''--database="(echo "${staging-db}")"''
                    "--database=sqlite:${cfg.kdc.database}"
                    "--source=heimdal"
                    ''--keytab="${cfg.kdc.primary.keytabs.hprop}"''
                  ] ++ cfg.kdc.primary.secondary-servers));
                ExecStartPost = pkgs.writeShellScript "kdc-hprop-cleanup.sh"
                  "${pkgs.coreutils}/bin/rm ${staging-db}";
              };
            };
          };

          paths.heimdal-hprop = mkIf hasSecondary {
            wantedBy = [ "heimdal-hprop.service" ];
            bindsTo = [ "heimdal-hprop.service" ];
            after = [ "heimdal-kdc.service" ];
            pathConfig = { PathModified = cfg.kdc.database; };
          };
        };

        networking.firewall = {
          allowedTCPPorts = [ 88 749 ];
          allowedUDPPorts = [ 88 464 ];
        };
      };
    };

  secondaryConfig = { config, lib, pkgs, ... }:
    let
      cfg = config.fudo.auth.kerberos;

      kdcConf = pkgs.writeText "kdc.conf.template" ''
        [kdc]
          database = {
            realm = ${cfg.realm}
            dbname = sqlite:${cfg.kdc.database}
            mkey_file = __KEY_FILE__
            log_file = /dev/null
          }

        [realms]
          ${cfg.realm} = {
            enable-http = false;
          }

        [libdefaults]
          default_realm = ${cfg.realm}
          allow_weak_crypto = false

        [logging]
          kdc = FILE:${cfg.kdc.state-directory}/kerberos.log
          default = FILE:${cfg.kdc.state-directory}/kerberos.log
      '';
    in {
      config = mkIf cfg.kdc.secondary.enable {

        users = {
          users."${cfg.user}" = {
            isSystemUser = true;
            group = cfg.group;
          };
          groups."${cfg.group}".members = [ cfg.user ];
        };

        systemd = {

          tmpfiles.rules =
            [ "f ${cfg.kdc.database} 0700 ${cfg.user} ${cfg.group} - -" ];

          services = {
            heimdal-kdc-secondary = {
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              description =
                "Heimdal Kerberos Key Distribution Center (secondary ticket server).";
              path = with pkgs; [ heimdal ];
              serviceConfig = {
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectControlGroups = true;
                ProtectKernelTunables = true;
                ProtectHostname = true;
                ProtectClock = true;
                ProtectKernelLogs = true;
                MemoryDenyWriteExecute = true;
                RestrictRealtime = true;
                LimitNOFILE = 4096;
                User = cfg.user;
                Group = cfg.group;
                Restart = "always";
                RestartSec = "5s";
                AmbientCapabilities = "CAP_NET_BIND_SERVICE";
                SecureBits = "keep-caps";
                RuntimeDirectory = "heimdal-kdc-secondary";
                ExecStart = let
                  ips = if (cfg.kdc.bind-addresses != [ ]) then
                    cfg.kdc.bind-addresses
                  else
                    [ "0.0.0.0" ];
                  bindClause = "--addresses=${concatStringsSep "," ips}";
                in "${pkgs.heimdal}/libexec/heimdal/kdc --config-file=${kdcConf} --ports=88 ${bindClause}";
              };
              unitConfig.ConditionPathExists =
                [ cfg.kdc.database cfg.kdc.secondary.keytabs.hpropd ];
            };

            "heimdal-hpropd@" = {
              description = "Heimdal propagation listener server.";
              path = with pkgs; [ heimdal ];
              serviceConfig = {
                StandardInput = "socket";
                StandardOutput = "socket";
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectControlGroups = true;
                ProtectKernelTunables = true;
                ProtectHostname = true;
                ProtectClock = true;
                ProtectKernelLogs = true;
                MemoryDenyWriteExecute = true;
                RestrictRealtime = true;
                LimitNOFILE = 4096;
                User = cfg.user;
                Group = cfg.group;
                Restart = "always";
                RestartSec = "5s";
                AmbientCapabilities = "CAP_NET_BIND_SERVICE";
                SecureBits = "keep-caps";
                ExecStart = concatStringsSep " " [
                  "${pkgs.heimdal}/libexec/heimdal/hpropd"
                  "--database=sqlite:${cfg.kdc.database}"
                  "--keytab=${cfg.kdc.secondary.keytabs.hpropd}"
                ];
              };
              unitConfig.ConditionPathExists =
                [ cfg.kdc.database cfg.kdc.secondary.keytabs.hpropd ];
            };
          };

          sockets.heimdal-hpropd = {
            wantedBy = [ "sockets.target" ];
            socketConfig = {
              ListenStream = "0.0.0.0:754";
              Accept = true;
            };
          };
        };

        networking.firewall = {
          allowedTCPPorts = [ 88 754 ];
          allowedUDPPorts = [ 88 ];
        };
      };
    };

in {
  options.fudo.auth.kerberos = with types; {
    kdc = {
      bind-addresses = mkOption {
        type = listOf str;
        description =
          "A list of IP addresses on which to bind. Default to all addresses.";
        default = [ ];
      };

      state-directory = mkOption {
        type = str;
        description = "Directory at which to store KDC server state.";
      };

      master-key-file = mkOption {
        type = str;
        description = "File containing the master key for this realm.";
      };

      database = mkOption {
        type = str;
        description = "Database file containing realm principals.";
        default =
          "${toplevel.config.fudo.auth.kerberos.kdc.state-directory}/realm.db";
      };

      primary = {
        enable = mkEnableOption "Enable Kerberos KDC server.";

        keytabs = {
          kadmind = mkOption {
            type = str;
            description = "Kerberos keytab for kadmind.";
          };

          kpasswdd = mkOption {
            type = str;
            description = "Kerberos keytab for kpasswdd.";
          };

          hprop = mkOption {
            type = str;
            description = "Kerberos keytab for hprop database propagation.";
          };
        };

        secondary-servers = mkOption {
          type = listOf str;
          description =
            "List of secondary servers to which the database should be propagated.";
          default = [ ];
        };

        acl = let
          aclEntry = { name, ... }:
            let principal = name;
            in {
              options = {
                principal = mkOption {
                  type = str;
                  description = "Principal to be granted permissions.";
                  default = principal;
                };

                perms = let
                  permList = [
                    "add"
                    "all"
                    "change-password"
                    "delete"
                    "get"
                    "get-keys"
                    "list"
                    "modify"
                  ];
                in mkOption {
                  type = listOf (enum permList);
                  description =
                    "List of permissions applied to this principal.";
                  default = [ ];
                };

                target = mkOption {
                  type = nullOr str;
                  description = "Principals to which these permissions apply.";
                  default = null;
                };
              };
            };
        in mkOption {
          type = attrsOf (submodule aclEntry);
          description = "Mapping of principals to a list of permissions.";
          default = { "*/root" = [ "all" ]; };
          example = {
            "*/root" = [ "all" ];
            "admin-user" = [ "add" "list" "modify" ];
          };
        };
      };

      secondary = {
        enable = mkEnableOption "Enable Kerberos KDC server.";

        keytabs = {
          hpropd = mkOption {
            type = str;
            description = "Kerberos keytab for the hpropd secondary server.";
          };
        };
      };
    };

    realm = mkOption {
      type = str;
      description = "Realm served by this KDC.";
    };

    user = mkOption {
      type = str;
      description = "User as which to run Kerberos KDC.";
      default = "kerberos";
    };

    group = mkOption {
      type = str;
      description = "Group as which to run Kerberos KDC.";
      default = "kerberos";
    };
  };

  imports = [ primaryConfig secondaryConfig ];
}
