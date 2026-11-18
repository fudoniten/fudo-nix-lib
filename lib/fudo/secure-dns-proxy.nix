{ lib, pkgs, config, ... }:

with lib;
let
  cfg = config.fudo.secure-dns-proxy;

in {
  options.fudo.secure-dns-proxy = with types; {
    enable =
      mkEnableOption "Enable a DNS server using an encrypted upstream source.";

    listen-port = mkOption {
      type = port;
      description = "Port on which to listen for DNS queries.";
      default = 53;
    };

    upstream-dns = mkOption {
      type = listOf str;
      description = ''
        The upstream DNS services to use, in a format useable by dnsproxy.

        See: https://github.com/AdguardTeam/dnsproxy
      '';
      default = [ "https://cloudflare-dns.com/dns-query" ];
    };

    bootstrap-dns = mkOption {
      type = str;
      description =
        "A simple DNS server from which HTTPS DNS can be bootstrapped, if necessary.";
      default = "1.1.1.1";
    };

    listen-ips = mkOption {
      type = listOf str;
      description = "A list of local IP addresses on which to listen.";
      default = [ "0.0.0.0" ];
    };

    allowed-networks = mkOption {
      type = nullOr (listOf str);
      description =
        "List of networks with which this job is allowed to communicate.";
      default = null;
    };

    user = mkOption {
      type = str;
      description = "User as which to run secure DNS proxy.";
      default = "secure-dns-proxy";
    };

    group = mkOption {
      type = str;
      description = "Group as which to run secure DNS proxy.";
      default = "secure-dns-proxy";
    };
  };

  config = mkIf cfg.enable (let
    upgrade-perms = cfg.listen-port <= 1024;
  in {
    users = mkIf upgrade-perms {
      users = {
        ${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
        };
      };

      groups = {
        ${cfg.group} = {
          members = [ cfg.user ];
        };
      };
    };

    systemd.services.secure-dns-proxy = {
      description = "DNS Proxy for secure DNS-over-HTTPS lookups.";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = let
        upstreams = concatMapStringsSep " " (u: "-u ${u}") cfg.upstream-dns;
        listens = concatMapStringsSep " " (l: "-l ${l}") cfg.listen-ips;
      in {
        ExecStart = "${pkgs.dnsproxy}/bin/dnsproxy -p ${
            toString cfg.listen-port
          } ${upstreams} ${listens} -b ${cfg.bootstrap-dns}";
        Restart = "always";
        LimitNOFILE = 49152;
        UMask = "0077";

        PrivateDevices = true;
        PrivateMounts = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "full";
        InaccessiblePaths = [ "/home" "/root" ];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        SystemCallFilter = [
          "~@clock @debug @module @mount @raw-io @reboot @swap @privileged @resources @cpu-emulation @obsolete"
        ];
      } // optionalAttrs (cfg.allowed-networks != null) {
        IPAddressAllow = cfg.allowed-networks;
        IPAddressDeny = "any";
      } // (if upgrade-perms then {
        # Privileged port: run as a fixed user that keeps CAP_NET_BIND_SERVICE.
        User = cfg.user;
        Group = cfg.group;
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        SecureBits = "keep-caps";
      } else {
        DynamicUser = true;
        PrivateUsers = true;
      });
    };
  });
}
