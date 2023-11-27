{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.adguard-dns-proxy;

  hostname = config.instance.hostname;

  get-basename = filename:
    head (builtins.match "^[a-zA-Z0-9]+-(.+)$" (baseNameOf filename));

  format-json-file = filename:
    pkgs.stdenv.mkDerivation {
      name = "formatted-${get-basename filename}";
      phases = [ "installPhase" ];
      buildInputs = with pkgs; [ python3 ];
      installPhase = "python -mjson.tool ${filename} > $out";
    };

  admin-passwd-file =
    pkgs.lib.passwd.stablerandom-passwd-file "adguard-dns-proxy-admin"
    config.instance.build-seed;

  filterOpts = {
    options = with types; {
      enable = mkOption {
        type = bool;
        description = "Enable this filter on DNS traffic.";
        default = true;
      };
      name = mkOption {
        type = str;
        description = "Name of this filter.";
      };
      url = mkOption {
        type = str;
        description = "URL to the filter itself.";
        default = true;
      };
    };
  };

  generate-config = { dns, http, filters, verbose, upstream-dns, bootstrap-dns
    , blocked-hosts, enable-dnssec, local-domain-name, ... }: {
      bind_host = http.listen-ip;
      bind_port = http.listen-port;
      users = [{
        name = "admin";
        password = pkgs.lib.passwd.bcrypt-passwd "adguard-dns-proxy-admin"
          admin-passwd-file;
      }];
      auth_attempts = 5;
      block_auth_min = 30;
      web_session_ttl = 720;
      dns = {
        bind_hosts = dns.listen-ips;
        port = dns.listen-port;
        upstream_dns = upstream-dns;
        bootstrap_dns = bootstrap-dns;
        enable_dnssec = enable-dnssec;
        local_domain_name = local-domain-name;
        protection_enabled = true;
        blocking_mode = "default";
        blocked_hosts = blocked-hosts;
        filtering_enabled = true;
        parental_enabled = false;
        safesearch_enabled = false;
        use_private_ptr_resolvers = cfg.dns.reverse-dns != [ ];
        local_ptr_upstreams = cfg.dns.reverse-dns;
      };
      tls.enabled = false;
      filters = imap1 (i: filter: {
        enabled = true;
        name = filter.name;
        url = filter.url;
      }) filters;
      dhcp.enabled = false;
      clients = [ ];
      verbose = verbose;
      schema_version = 10;
    };

  generate-config-file = opts:
    format-json-file (pkgs.writeText "adguard-dns-proxy-config.yaml"
      (builtins.toJSON (generate-config opts)));

in {
  options.fudo.adguard-dns-proxy = with types; {
    enable = mkEnableOption "Enable AdGuardHome DNS proxy.";

    dns = {
      listen-ips = mkOption {
        type = listOf str;
        description = "IP on which to listen for incoming DNS requests.";
        default = [ "0.0.0.0" ];
      };

      listen-port = mkOption {
        type = port;
        description = "Port on which to listen for DNS queries.";
        default = 53;
      };

      reverse-dns = mkOption {
        type = listOf str;
        description =
          "DNS servers on which to perform reverse lookups for private addresses (if any).";
        default = [ ];
      };
    };

    http = {
      listen-ip = mkOption {
        type = str;
        description = "IP on which to listen for incoming HTTP requests.";
      };

      listen-port = mkOption {
        type = port;
        description = "Port on which to listen for incoming HTTP queries.";
        default = 8053;
      };
    };

    filters = mkOption {
      type = listOf (submodule filterOpts);
      description = "List of filters to apply to DNS traffic.";
      default = [
        {
          name = "AdGuard DNS filter";
          url =
            "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt";
        }
        {
          name = "AdAway Default Blocklist";
          url = "https://adaway.org/hosts.txt";
        }
        {
          name = "MalwareDomainList.com Hosts List";
          url = "https://www.malwaredomainlist.com/hostslist/hosts.txt";
        }
        {
          name = "OISD.NL Blocklist";
          url = "https://abp.oisd.nl/";
        }
      ];
    };

    blocked-hosts = mkOption {
      type = listOf str;
      description = "List of hosts to explicitly block.";
      default = [ "version.bind" "id.server" "hostname.bind" ];
    };

    enable-dnssec = mkOption {
      type = bool;
      description = "Enable DNSSEC";
      default = true;
    };

    upstream-dns = mkOption {
      type = listOf str;
      description = ''
        List of upstream DNS services to use.

        See https://github.com/AdguardTeam/dnsproxy for correct formatting.
      '';
      default = [
        "https://1.1.1.1/dns-query"
        "https://1.0.0.1/dns-query"
        # These 11 addrs send the network, so the response can prefer closer answers
        "https://9.9.9.11/dns-query"
        "https://149.112.112.11/dns-query"
        "https://2620:fe::11/dns-query"
        "https://2620:fe::fe:11/dns-query"
      ];
    };

    bootstrap-dns = mkOption {
      type = listOf str;
      description = "List of DNS servers used to bootstrap DNS-over-HTTPS.";
      default = [
        "1.1.1.1"
        "1.0.0.1"
        "9.9.9.9"
        "149.112.112.112"
        "2620:fe::10"
        "2620:fe::fe:10"
      ];
    };

    allowed-networks = mkOption {
      type = nullOr (listOf str);
      description =
        "Optional list of networks with which this job may communicate.";
      default = null;
    };

    user = mkOption {
      type = str;
      description = "User as which this job will run.";
      default = "adguard-dns-proxy";
    };

    local-domain-name = mkOption {
      type = str;
      description = "Local domain name.";
    };

    verbose = mkEnableOption "Keep verbose logs.";
  };

  config = mkIf cfg.enable (let
    upgrade-perms = cfg.dns.listen-port <= 1024 || cfg.http.listen-port <= 1024;
  in {
    users = mkIf upgrade-perms {
      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.user;
      };

      groups.${cfg.user} = { members = [ cfg.user ]; };
    };

    fudo = {
      secrets.host-secrets.${hostname} = {
        adguard-dns-proxy-admin-password = {
          source-file = admin-passwd-file;
          target-file = "/run/adguard-dns-proxy/admin.passwd";
          user = "root";
        };
      };

      system.services.adguard-dns-proxy =
        let cfg-path = "/run/adguard-dns-proxy/config.yaml";
        in {
          description =
            "DNS Proxy for ad filtering and DNS-over-HTTPS lookups.";
          wantedBy = [ "default.target" ];
          after = [ "syslog.target" ];
          requires = [ "network.target" ];
          privateNetwork = false;
          requiredCapabilities = optional upgrade-perms "CAP_NET_BIND_SERVICE";
          restartWhen = "always";
          addressFamilies = null;
          networkWhitelist = cfg.allowed-networks;
          user = mkIf upgrade-perms cfg.user;
          runtimeDirectory = "adguard-dns-proxy";
          stateDirectory = "adguard-dns-proxy";
          preStart = ''
            cp ${generate-config-file cfg} ${cfg-path};
            chown $USER ${cfg-path};
            chmod u+w ${cfg-path};
          '';

          execStart = let
            args = [
              "--no-check-update"
              "--work-dir /var/lib/adguard-dns-proxy"
              "--pidfile /run/adguard-dns-proxy/adguard-dns-proxy.pid"
              "--host ${cfg.http.listen-ip}"
              "--port ${toString cfg.http.listen-port}"
              "--config ${cfg-path}"
            ];
            arg-string = concatStringsSep " " args;
          in "${pkgs.adguardhome}/bin/adguardhome ${arg-string}";
        };
    };
  });
}
