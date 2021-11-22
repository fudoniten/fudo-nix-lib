{ lib, config, pkgs, ... }:

with lib;
let
  cfg = config.fudo.local-network;

  join-lines = concatStringsSep "\n";

  traceout = out: builtins.trace out out;

in {

  options.fudo.local-network = with types; {

    enable = mkEnableOption "Enable local network configuration (DHCP & DNS).";

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
      description = "A list of IPs on which to server DNS queries.";
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

    recursive-resolver = mkOption {
      type = str;
      description = "DNS nameserver to use for recursive resolution.";
      default = "1.1.1.1 port 53";
    };

    search-domains = mkOption {
      type = listOf str;
      description = "A list of domains which clients should consider local.";
      example = [ "my-domain.com" "other-domain.com" ];
      default = [ ];
    };

    zone-definition = let
      zoneOpts = import ../types/zone-definition.nix { inherit lib; };
    in mkOption {
      type = submodule zoneOpts;
      description = "Definition of network zone to be served by local server.";
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
      other-hosts = filterAttrs
        (hostname: hostOpts: hostname != config.instance.hostname)
        cfg.zone-definition.hosts;
    in mapAttrs' (hostname: hostOpts:
      nameValuePair hostOpts.ipv4-address ["${hostname}.${cfg.domain}" hostname])
      other-hosts;
    
    services.dhcpd4 = let
      zone = cfg.zone-definition;
    in {
      enable = true;

      machines = mapAttrsToList (hostname: hostOpts: {
        ethernetAddress = hostOpts.mac-address;
        hostName = hostname;
        ipAddress = hostOpts.ipv4-address;
      }) (filterAttrs (host: hostOpts:
        hostOpts.mac-address != null && hostOpts.ipv4-address != null)
        zone.hosts);

      interfaces = cfg.dhcp-interfaces;

      extraConfig = ''
        subnet ${pkgs.lib.fudo.ip.getNetworkBase cfg.network} netmask ${
          pkgs.lib.fudo.ip.maskFromV32Network cfg.network
        } {
          authoritative;
          option subnet-mask ${pkgs.lib.fudo.ip.maskFromV32Network cfg.network};
          option broadcast-address ${pkgs.lib.fudo.ip.networkMaxIp cfg.network};
          option routers ${cfg.gateway};
          option domain-name-servers ${concatStringsSep " " cfg.dns-servers};
          option domain-name "${cfg.domain}";
          option domain-search "${
            concatStringsSep " " ([ cfg.domain ] ++ cfg.search-domains)
          }";
          range ${pkgs.lib.fudo.ip.networkMinIp cfg.dhcp-dynamic-network} ${
            pkgs.lib.fudo.ip.networkMaxButOneIp cfg.dhcp-dynamic-network
          };
        }
      '';
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

      ipToBlock = ip:
        concatStringsSep "." (reverseList (take 3 (splitString "." ip)));
      compactHosts =
        mapAttrsToList (host: data: data // { host = host; }) zone.hosts;
      hostsByBlock =
        groupBy (host-data: ipToBlock host-data.ipv4-address) compactHosts;
      hostPtrRecord = host-data:
        "${
          last (splitString "." host-data.ipv4-address)
        } IN PTR ${host-data.host}.${cfg.domain}.";

      blockZones = mapAttrsToList blockHostsToZone hostsByBlock;

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

    in {
      enable = true;
      cacheNetworks = [ cfg.network "localhost" "localnets" ];
      forwarders = [ cfg.recursive-resolver ];
      listenOn = cfg.dns-listen-ips;
      extraOptions = concatStringsSep "\n" [
        "dnssec-enable yes;"
        "dnssec-validation yes;"
        "auth-nxdomain no;"
        "recursion yes;"
        "allow-recursion { any; };"
      ];
      zones = [{
        master = true;
        name = cfg.domain;
        file = pkgs.writeText "${cfg.domain}-zone" ''
          @ IN SOA ns1.${cfg.domain}. hostmaster.${cfg.domain}. (
            ${toString config.instance.build-timestamp}
            5m
            2m
            6w
            5m)

          $TTL 1h

          @ IN NS ns1.${cfg.domain}.

          $ORIGIN ${cfg.domain}.

          $TTL 30m

          ${optionalString (zone.gssapi-realm != null)
          ''_kerberos IN TXT "${zone.gssapi-realm}"''}

          ${join-lines
          (imap1 (i: server-ip: "ns${toString i} IN A ${server-ip}")
            cfg.dns-servers)}
          ${join-lines (mapAttrsToList hostARecord zone.hosts)}
          ${join-lines (mapAttrsToList hostSshFpRecords zone.hosts)}
          ${join-lines (mapAttrsToList cnameRecord zone.aliases)}
          ${join-lines zone.verbatim-dns-records}
          ${pkgs.lib.fudo.dns.srvRecordsToBindZone zone.srv-records}
          ${join-lines cfg.extra-records}
        '';
      }] ++ blockZones;
    };
  };
}
