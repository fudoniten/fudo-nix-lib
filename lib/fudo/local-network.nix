{ lib, config, pkgs, ... }:

with lib;
let
  cfg = config.fudo.local-network;

  join-lines = concatStringsSep "\n";

  inherit (pkgs.lib.ip)
    getNetworkBase maskFromV32Network networkMinIp networkMaxIp;

in {

  options.fudo.local-network = with types; {

    enable = mkEnableOption "Enable local network configuration (DHCP & DNS).";

    state-directory = mkOption {
      type = str;
      description = "Path at which to store server state.";
    };

    domain = mkOption {
      type = str;
      description = "The domain to use for the local network.";
    };

    dns-servers = mkOption {
      type = listOf str;
      description = "A list of domain name servers to pass to local clients.";
    };

    dhcp-interfaces = mkOption {
      type = listOf str;
      description = "A list of interfaces on which to serve DHCP.";
    };

    dns-listen-ips = mkOption {
      type = listOf str;
      description = "A list of IPv4 addresses on which to server DNS queries.";
    };

    dns-listen-ipv6s = mkOption {
      type = listOf str;
      description = "A list of IPv6 addresses on which to server DNS queries.";
      default = [ ];
    };

    gateway = mkOption {
      type = str;
      description = "The gateway to use for the local network.";
    };

    network = mkOption {
      type = str;
      description = "Network to treat as local.";
      example = "10.0.0.0/16";
    };

    dhcp-dynamic-network = mkOption {
      type = str;
      description = ''
        The network from which to dynamically allocate IPs via DHCP.

        Must be a subnet of <network>.
      '';
      example = "10.0.1.0/24";
    };

    enable-reverse-mappings = mkOption {
      type = bool;
      description = "Genereate PTR reverse lookup records.";
      default = false;
    };

    # recursive-resolver = mkOption {
    #   type = str;
    #   description = "DNS nameserver to use for recursive resolution.";
    #   default = "1.1.1.1 port 53";
    # };

    recursive-resolver = {
      host = mkOption {
        type = str;
        description = "DNS server host or (preferably) IP.";
      };
      port = mkOption {
        type = port;
        description = "Remote host port for DNS queries.";
        default = 53;
      };
    };

    search-domains = mkOption {
      type = listOf str;
      description = "A list of domains which clients should consider local.";
      example = [ "my-domain.com" "other-domain.com" ];
      default = [ ];
    };

    zone-definition =
      let zoneOpts = import ../types/zone-definition.nix { inherit lib; };
      in mkOption {
        type = submodule zoneOpts;
        description =
          "Definition of network zone to be served by local server.";
        default = { };
      };

    extra-records = mkOption {
      type = listOf str;
      description = "Extra records to add to the local zone.";
      default = [ ];
    };
  };

  config = mkIf cfg.enable {

    fudo.system.hostfile-entries = let
      other-hosts =
        filterAttrs (hostname: hostOpts: hostname != config.instance.hostname)
        cfg.zone-definition.hosts;
    in mapAttrs' (hostname: hostOpts:
      nameValuePair hostOpts.ipv4-address [
        "${hostname}.${cfg.domain}"
        hostname
      ]) other-hosts;

    services.kea.dhcp4 = {
      enable = true;
      settings = {
        interfaces-config.interfaces = cfg.dhcp-interfaces;
        lease-database = {
          name = "${cfg.state-directory}/dhcp4.leases";
          type = "memfile";
          persist = true;
        };
        valid-lifetime = 4000;
        rebind-timer = 2000;
        renew-timer = 1000;
        option-data = let joinList = concatStringsSep ", ";
        in [
          {
            name = "domain-name-servers";
            data = joinList cfg.dns-servers;
          }
          {
            name = "subnet-mask";
            data = maskFromV32Network cfg.network;
          }
          {
            name = "broadcast-address";
            data = networkMaxIp cfg.network;
          }
          {
            name = "routers";
            data = cfg.gateway;
          }
          {
            name = "domain-name";
            data = cfg.domain;
          }
          {
            name = "domain-search";
            data = joinList ([ cfg.domain ] ++ cfg.search-domains);
          }
        ];
        subnet4 = [{
          pools = [{
            pool = let
              minIp = networkMinIp cfg.dhcp-dynamic-network;
              maxIp = networkMaxIp cfg.dhcp-dynamic-network;
            in "${minIp} - ${maxIp}";
          }];
          subnet = cfg.network;
          reservations = let
            hostsWithMac = filterAttrs (_: hostOpts:
              !isNull hostOpts.mac-address && !isNull hostOpts.ipv4-address)
              cfg.zone-definition.hosts;
          in mapAttrsToList (hostname:
            { mac-address, ipv4-address, ... }: {
              hw-address = mac-address;
              # hostName = hostname;
              ip-address = ipv4-address;
            }) hostsWithMac;
        }];
      };
    };

    services.bind = let
      blockHostsToZone = block: hosts-data: {
        master = true;
        name = "${block}.in-addr.arpa";
        file = let
          # We should add these...but need a domain to assign them to.
          # ip-last-el = ip: toInt (last (splitString "." ip));
          # used-els = map (host-data: ip-last-el host-data.ipv4-address) hosts-data;
          # unused-els = subtractLists used-els (map toString (range 1 255));

        in pkgs.writeText "db.${block}-zone" ''
          $ORIGIN ${block}.in-addr.arpa.
          $TTL 1h

          @ IN SOA ns1.${cfg.domain}. hostmaster.${cfg.domain}. (
            ${toString config.instance.build-timestamp}
            1800
            900
            604800
            1800)

          @ IN NS ns1.${cfg.domain}.

          ${join-lines (map hostPtrRecord hosts-data)}
        '';
      };

      filterRedundantIps = official-hosts: hosts:
        let host-by-ip = groupBy (hostOpts: hostOpts.ipv4-address) hosts;
        in filter (hostOpts:
          if (length (getAttr hostOpts.ipv4-address host-by-ip) == 1) then
            true
          else
            elem hostOpts.hostname official-hosts) hosts;
      ipTo24Block = ip:
        concatStringsSep "." (reverseList (take 3 (splitString "." ip)));
      hostsByBlock = official-hosts:
        groupBy (host-data: ipTo24Block host-data.ipv4-address)
        (filterRedundantIps official-hosts (attrValues zone.hosts));
      hostPtrRecord = host-data:
        "${
          last (splitString "." host-data.ipv4-address)
        } IN PTR ${host-data.hostname}.${cfg.domain}.";

      blockZones = official-hosts:
        mapAttrsToList blockHostsToZone (hostsByBlock official-hosts);

      hostARecord = host: data: "${host} IN A ${data.ipv4-address}";
      hostSshFpRecords = host: data:
        let
          ssh-fingerprints = if (hasAttr host known-hosts) then
            known-hosts.${host}.ssh-fingerprints
          else
            [ ];
        in join-lines
        (map (sshfp: "${host} IN SSHFP ${sshfp}") ssh-fingerprints);
      cnameRecord = alias: host: "${alias} IN CNAME ${host}";

      zone = cfg.zone-definition;

      known-hosts = config.fudo.hosts;

      domain-name = config.instance.local-domain;

      domain-hosts = attrNames
        (filterAttrs (_: hostOpts: hostOpts.domain == domain-name)
          config.fudo.hosts);

    in {
      enable = true;
      cacheNetworks = [ cfg.network "localhost" "localnets" ];
      forwarders = [
        "${cfg.recursive-resolver.host} port ${
          toString cfg.recursive-resolver.port
        }"
      ];
      listenOn = cfg.dns-listen-ips;
      listenOnIpv6 = cfg.dns-listen-ipv6s;
      extraOptions = concatStringsSep "\n" [
        "dnssec-validation yes;"
        "auth-nxdomain no;"
        "recursion yes;"
        "allow-recursion { any; };"
      ];
      zones = [{
        master = true;
        name = cfg.domain;
        file = let
          zone-data =
            pkgs.lib.dns.zoneToZonefile config.instance.build-timestamp
            cfg.domain zone;
        in pkgs.writeText "zone-${cfg.domain}" zone-data;
      }] ++ (optionals cfg.enable-reverse-mappings (blockZones domain-hosts));
    };
  };
}
