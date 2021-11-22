{ lib, pkgs, config, ... }:

with lib;
let
  cfg = config.fudo.secure-dns-proxy;

  fudo-lib = import ../fudo-lib.nix { lib = lib; };

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

    fudo.system.services.secure-dns-proxy = {
      description = "DNS Proxy for secure DNS-over-HTTPS lookups.";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      privateNetwork = false;
      requiredCapabilities = mkIf upgrade-perms [ "CAP_NET_BIND_SERVICE" ];
      restartWhen = "always";
      addressFamilies = [ "AF_INET" "AF_INET6" ];
      networkWhitelist = cfg.allowed-networks;
      user = mkIf upgrade-perms cfg.user;
      group = mkIf upgrade-perms cfg.group;

      execStart = let
        upstreams = map (upstream: "-u ${upstream}") cfg.upstream-dns;
        upstream-line = concatStringsSep " " upstreams;
        listen-line =
          concatStringsSep " " (map (listen: "-l ${listen}") cfg.listen-ips);
      in "${pkgs.dnsproxy}/bin/dnsproxy -p ${
        toString cfg.listen-port
      } ${upstream-line} ${listen-line} -b ${cfg.bootstrap-dns}";
    };
  });
}
