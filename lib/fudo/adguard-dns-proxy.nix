{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.adguard-dns-proxy;

  inherit (config.instance) hostname;

  get-basename = filename:
    head (builtins.match "^[a-zA-Z0-9]+-(.+)$" (baseNameOf filename));

  format-json-file = filename:
    pkgs.stdenv.mkDerivation {
      name = "formatted-${get-basename filename}";
      phases = [ "installPhase" ];
      buildInputs = with pkgs; [ python3 ];
      installPhase = "python -mjson.tool ${filename} > $out";
    };

  default-passwd-file =
    pkgs.lib.passwd.stablerandom-passwd-file "adguard-dns-proxy-admin"
    config.instance.build-seed;

  admin-passwd-file = if (cfg.admin-password-file != null) then
    cfg.admin-password-file
  else
    default-passwd-file;

  # Reads the password on stdin and prints its bcrypt hash. Takes no path: the
  # source is a systemd credential whose location is only known at runtime, so
  # the caller pipes it in.
  #
  # `-i` reads stdin; `-b` takes the password as an argv, so piping into it
  # leaves htpasswd with no password at all. Reading stdin also keeps the
  # plaintext off the process table, which `-b "$(cat ...)"` would not.
  #
  # AdGuardHome rejects the `$2y$` prefix htpasswd emits, hence the rewrite to
  # `$2a$` -- the same substitution lib/lib/passwd.nix makes, and it needs its
  # closing delimiter or sed dies with "unterminated `s' command".
  bcrypt-stdin-cmd = ''
    ${pkgs.apacheHttpd}/bin/htpasswd -niBC 10 "" |
      tr -d ':\n' |
      sed 's/$2y/$2a/'
  '';

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

  # upstream_mode as a string key was introduced in AdGuard Home v0.107.44.
  # Older versions use the legacy all_servers / fastest_addr booleans instead.
  useUpstreamModeKey = lib.versionAtLeast pkgs.adguardhome.version "0.107.44";

  generate-config = { dns, http, filters, verbose, upstream-dns, bootstrap-dns
    , blocked-hosts, enable-dnssec, domain-upstreams, local-domain-name, ... }:
    let
      upstreamDnsEntries = mapAttrsToList (_: opts:
        let domainClause = concatStringsSep "/" opts.domains;
        in "[/${domainClause}/]${opts.upstream}") domain-upstreams;
      upstreamModeAttrs = if useUpstreamModeKey then {
        upstream_mode = cfg.upstream-mode;
      } else if cfg.upstream-mode == "parallel" then {
        all_servers = true;
      } else if cfg.upstream-mode == "fastest_addr" then {
        fastest_addr = true;
      } else
        { };
    in {
      bind_host = http.listen-ip;
      bind_port = http.listen-port;
      users = [{
        name = "admin";
        password = "@ADMIN_PASSWD_HASH@";
      }];
      auth_attempts = 5;
      block_auth_min = 30;
      web_session_ttl = 720;
      dns = {
        bind_hosts = dns.listen-ips;
        port = dns.listen-port;
        upstream_dns = upstream-dns ++ upstreamDnsEntries;
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
        hostsfile_enabled = false;
      } // upstreamModeAttrs // optionalAttrs (cfg.fallback-dns != [ ]) {
        fallback_dns = cfg.fallback-dns;
      } // optionalAttrs (cfg.upstream-timeout != null) {
        upstream_timeout = cfg.upstream-timeout;
      };
      tls.enabled = false;
      filters = imap1 (i:
        { name, url, ... }: {
          enabled = true;
          inherit name url;
        }) filters;
      dhcp.enabled = false;
      clients = [ ];
      inherit verbose;
      schema_version = 10;
    };

  generate-config-file = opts:
    format-json-file (pkgs.writeText "adguard-dns-proxy-config.yaml"
      (builtins.toJSON (generate-config opts)));

in {
  options.fudo.adguard-dns-proxy = with types; {
    enable = mkEnableOption "Enable AdGuardHome DNS proxy.";

    admin-password-file = mkOption {
      type = nullOr str;
      description = ''
        Path, on the target host, to a file holding the admin password.

        A runtime path, deliberately typed `str` rather than `path`: a `path`
        would be copied into the store at evaluation, which is the opposite of
        the point. It is read at service start, never at build time.

        It needs to be readable by root and nothing more. The service runs as
        a DynamicUser and reads the password through a systemd credential, so
        do not try to give that account ownership of the file: the account is
        transient and does not exist when the secret is decrypted, so the
        chown would fail at boot. Root-owned 0400 is right.

        Null means generate one from the build seed, as this module always
        did. Anything else -- a secret placed by Aegis, say -- takes over, and
        the legacy `fudo.secrets` copy is not declared at all: two pipelines
        deploying one secret is how you get a value that depends on which unit
        won.
      '';
      default = null;
      example = "/run/aegis/secrets/adguard.passwd";
    };

    admin-password-units = mkOption {
      type = listOf str;
      description = ''
        Units that must have completed before `admin-password-file` exists.

        Named rather than inferred, because this module has no idea what put
        the file there. Order against the specific unit that writes it, not a
        target that merely contains it: a target activates even when a member
        failed, and the service would then start and read nothing.

        Ignored when `admin-password-file` is null -- the generated password
        is a store path and is there from the start.
      '';
      default = [ ];
      example = [ "aegis-secret-adguard.passwd.service" ];
    };

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

    domain-upstreams = mkOption {
      type = attrsOf (submodule ({ name, ... }: {
        options = {
          domains = mkOption {
            type = listOf str;
            description =
              "List of domains to route to a specific upstream DNS target.";
            default = [ name ];
          };

          upstream = mkOption {
            type = str;
            description = "Upstream DNS target, in {ip}:{port} format.";
          };
        };
      }));
      default = { };
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
        {
          name = "FireBog Easy Privacy";
          url = "https://v.firebog.net/hosts/Easyprivacy.txt";
        }
        {
          name = "FireBog Easy Ads";
          url = "https://v.firebog.net/hosts/Easylist.txt";
        }
        {
          name = "FireBog Easy Admiral";
          url = "https://v.firebog.net/hosts/Admiral.txt";
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
        # "https://2620:fe::11/dns-query"
        # "https://2620:fe::fe:11/dns-query"
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

    upstream-mode = mkOption {
      type = enum [ "load_balance" "parallel" "fastest_addr" ];
      default = "load_balance";
      description = ''
        How AdGuard Home selects among multiple upstream-dns entries.

        load_balance: weighted-random favouring upstreams with fewer failures /
          lower latency. One query → one upstream. Health-aware, but a newly-dead
          upstream can still incur a per-query timeout until its weight drops.

        parallel: sends every query to all upstreams simultaneously and uses the
          first response. Best failover (a dead node costs almost nothing) at the
          cost of N× upstream traffic.

        fastest_addr: queries all upstreams, then returns the answer whose
          resolved IP has the lowest ping latency. Niche use-case.
      '';
    };

    fallback-dns = mkOption {
      type = listOf str;
      default = [ ];
      description = ''
        Resolvers used only when all primary upstream-dns servers fail to respond
        (timeout / network error). Does NOT trigger on SERVFAIL or empty answers.
        Omitted from the generated config when the list is empty.

        Entry syntax is the same as upstream-dns: plain ip, ip:port, or an
        encrypted scheme (tls://, https://, quic://). Per-domain routing prefixes
        ([/domain/]) are also valid.
      '';
    };

    upstream-timeout = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        AdGuard upstream_timeout duration (e.g. "10s"). When fallback-dns is set
        and all primary upstreams are down, each query stalls for this duration
        before fallback answers. Omitted when null (AdGuard default applies).
      '';
    };
  };

  config = mkIf cfg.enable {
    # Only when this module owns the password. `fudo.secrets` encrypts
    # `source-file` in a derivation -- `age -a -r <key> -o $out <source-file>`
    # -- so it is read on the *builder*. Handing it a path under /run made
    # every build fail with "failed to open input file", because that file
    # exists only on the target host, only after something has written it.
    #
    # Whoever supplies `admin-password-file` supplies the delivery too, so
    # there is nothing for the legacy pipeline to do here.
    fudo = mkIf (cfg.admin-password-file == null) {
      secrets.host-secrets.${hostname} = {
        adguard-dns-proxy-admin-password = {
          source-file = default-passwd-file;
          target-file = "/run/adguard-dns-proxy/admin.passwd";
          user = "root";
        };
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ cfg.dns.listen-port ];
      allowedUDPPorts = [ cfg.dns.listen-port ];
    };

    systemd.services.adguard-dns-proxy = {
      description = "DNS proxy for ad filtering and DNS-over-HTTPS lookups.";
      wantedBy = [ "default.target" ];
      after = [ "network.target" ] ++ cfg.admin-password-units;
      requires = [ "network.target" ] ++ cfg.admin-password-units;
      serviceConfig = {
        # This service runs as a DynamicUser, so it cannot read a root-owned
        # 0400 secret -- and it cannot be given ownership of one either: the
        # account is transient, allocated when the unit starts, so it does not
        # exist at the point the secret is decrypted. Chowning the secret to
        # it would fail at boot, before the service ever ran.
        #
        # LoadCredential is the mechanism for exactly this. PID 1 opens the
        # source as root, copies the contents into a per-unit tmpfs, and
        # exposes it at $CREDENTIALS_DIRECTORY owned by the service user and
        # readable by nobody else. It is torn down when the unit stops, so no
        # copy outlives the service.
        #
        # It also fails closed: a source that is missing or unreadable stops
        # the unit rather than starting it without a password.
        LoadCredential = [ "admin-passwd:${admin-passwd-file}" ];

        # The hash is substituted here rather than baked into the generated
        # config, so the store copy carries a placeholder and the real hash
        # only ever exists under /run.
        #
        # No `+` prefix: this runs as the service user, which is what makes
        # the config.yaml it writes readable by the service without a chown.
        # Reading the password is the only thing that needed privilege, and
        # the credential has already dealt with that.
        #
        # `set -euo pipefail` is load-bearing: without it a failure here
        # leaves ADMIN_PASSWD_HASH empty and the service starts with an empty
        # admin hash, which is worse than not starting.
        ExecStartPre = pkgs.writeShellScript "adguardsProxyPrestart.sh" ''
          set -euo pipefail

          ADMIN_PASSWD_HASH=$(
            cat "$CREDENTIALS_DIRECTORY/admin-passwd" | ${bcrypt-stdin-cmd}
          )
          ${pkgs.gnused}/bin/sed "s|@ADMIN_PASSWD_HASH@|$ADMIN_PASSWD_HASH|" \
            ${generate-config-file cfg} > $RUNTIME_DIRECTORY/config.yaml
        '';
        ExecStart = pkgs.writeShellScript "adguardProxyStart.sh"
          (concatStringsSep " " [
            "${pkgs.adguardhome}/bin/AdGuardHome"
            "--no-check-update"
            "--work-dir /var/lib/adguard-dns-proxy"
            "--pidfile /run/adguard-dns-proxy.pid"
            "--host ${cfg.http.listen-ip}"
            "--port ${toString cfg.http.listen-port}"
            "--config $RUNTIME_DIRECTORY/config.yaml"
          ]);
        AmbientCapabilities =
          optional (cfg.dns.listen-port <= 1024 || cfg.http.listen-port <= 1024)
          [ "CAP_NET_BIND_SERVICE" ];
        DynamicUser = true;
        RuntimeDirectory = "adguard-dns-proxy";
        StateDirectory = "adguard-dns-proxy";
      };
    };

    # system.services.adguard-dns-proxy =
    #   let cfg-path = "/run/adguard-dns-proxy/config.yaml";
    #   in {
    #     description =
    #       "DNS Proxy for ad filtering and DNS-over-HTTPS lookups.";
    #     wantedBy = [ "default.target" ];
    #     after = [ "syslog.target" ];
    #     requires = [ "network.target" ];
    #     privateNetwork = false;
    #     requiredCapabilities = optional upgrade-perms "CAP_NET_BIND_SERVICE";
    #     restartWhen = "always";
    #     addressFamilies = null;
    #     networkWhitelist = cfg.allowed-networks;
    #     user = mkIf upgrade-perms cfg.user;
    #     runtimeDirectory = "adguard-dns-proxy";
    #     stateDirectory = "adguard-dns-proxy";
    #     preStart = ''
    #       cp ${generate-config-file cfg} ${cfg-path};
    #       chown $USER ${cfg-path};
    #       chmod u+w ${cfg-path};
    #     '';

    #     execStart = let
    #       args = [
    #         "--no-check-update"
    #         "--work-dir /var/lib/adguard-dns-proxy"
    #         "--pidfile /run/adguard-dns-proxy/adguard-dns-proxy.pid"
    #         "--host ${cfg.http.listen-ip}"
    #         "--port ${toString cfg.http.listen-port}"
    #         "--config ${cfg-path}"
    #       ];
    #       arg-string = concatStringsSep " " args;
    #     in "${pkgs.adguardhome}/bin/adguardhome ${arg-string}";
    #   };
  };
}
