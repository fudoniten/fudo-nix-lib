{ lib, config, pkgs, ... }:

with lib;
let
  cfg = config.fudo.dns;

  join-lines = concatStringsSep "\n";

  domainOpts = { domain, ... }: {
    options = with types; {
      dnssec = mkOption {
        type = bool;
        description = "Enable DNSSEC security for this zone.";
        default = true;
      };

      dmarc-report-address = mkOption {
        type = nullOr str;
        description = "The email to use to recieve DMARC reports, if any.";
        example = "admin-user@domain.com";
        default = null;
      };

      zone-definition = mkOption {
        type = submodule (import ../types/zone-definition.nix);
        description = "Definition of network zone to be served by local server.";
      };

      default-host = mkOption {
        type = str;
        description = "The host to which the domain should map by default.";
      };

      mx = mkOption {
        type = listOf str;
        description = "The hosts which act as the domain mail exchange.";
        default = [];
      };

      gssapi-realm = mkOption {
        type = nullOr str;
        description = "The GSSAPI realm of this domain.";
        default = null;
      };
    };
  };

  networkHostOpts = import ../types/network-host.nix { inherit lib; };

  hostRecords = hostname: nethost-data: let
    # FIXME: RP doesn't work.
    # generic-host-records = let
    #   host-data = if (hasAttr hostname config.fudo.hosts) then config.fudo.hosts.${hostname} else null;
    # in
    #   if (host-data == null) then [] else (
    #     (map (sshfp: "${hostname} IN SSHFP ${sshfp}") host-data.ssh-fingerprints) ++ (optional (host-data.rp != null) "${hostname} IN RP ${host-data.rp}")
    #   );
    sshfp-records = if (hasAttr hostname config.fudo.hosts) then
      (map (sshfp: "${hostname} IN SSHFP ${sshfp}")
        config.fudo.hosts.${hostname}.ssh-fingerprints)
                    else [];
    a-record = optional (nethost-data.ipv4-address != null) "${hostname} IN A ${nethost-data.ipv4-address}";
    aaaa-record = optional (nethost-data.ipv6-address != null) "${hostname} IN AAAA ${nethost-data.ipv6-address}";
    description-record = optional (nethost-data.description != null) "${hostname} IN TXT \"${nethost-data.description}\"";
  in
    join-lines (a-record ++ aaaa-record ++ description-record ++ sshfp-records);

  makeSrvRecords = protocol: type: records:
    join-lines (map (record:
      "_${type}._${protocol} IN SRV ${toString record.priority} ${
        toString record.weight
      } ${toString record.port} ${toString record.host}.") records);

  makeSrvProtocolRecords = protocol: types:
    join-lines (mapAttrsToList (makeSrvRecords protocol) types);

  cnameRecord = alias: host: "${alias} IN CNAME ${host}";

  mxRecords = mxs: concatStringsSep "\n" (map (mx: "@ IN MX 10 ${mx}.") mxs);

  dmarcRecord = dmarc-email:
    optionalString (dmarc-email != null) ''
      _dmarc IN TXT "v=DMARC1;p=quarantine;sp=quarantine;rua=mailto:${dmarc-email};"'';

  nsRecords = domain: ns-hosts:
    join-lines
      (mapAttrsToList (host: _: "@ IN NS ${host}.${domain}.") ns-hosts);

in {

  options.fudo.dns = with types; {
    enable = mkEnableOption "Enable master DNS services.";

    # FIXME: This should allow for AAAA addresses too...
    nameservers = mkOption {
      type = attrsOf (submodule networkHostOpts);
      description = "Map of domain nameserver FQDNs to IP.";
      example = {
        "ns1.domain.com" = {
          ipv4-address = "1.1.1.1";
          description = "my fancy dns server";
        };
      };
    };

    identity = mkOption {
      type = str;
      description = "The identity (CH TXT ID.SERVER) of this host.";
    };

    domains = mkOption {
      type = attrsOf (submodule domainOpts);
      default = { };
      description = "A map of domain to domain options.";
    };

    listen-ips = mkOption {
      type = listOf str;
      description = "A list of IPs on which to listen for DNS queries.";
      example = [ "1.2.3.4" ];
    };

    state-directory = mkOption {
      type = str;
      description = "Path at which to store nameserver state, including DNSSEC keys.";
      default = "/var/lib/nsd";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
    
    fudo.nsd = {
      enable = true;
      identity = cfg.identity;
      interfaces = cfg.listen-ips;
      stateDir = cfg.state-directory;
      zones = mapAttrs' (dom: dom-cfg: let
        net-cfg = dom-cfg.zone-definition;
      in nameValuePair "${dom}." {
        dnssec = dom-cfg.dnssec;

        data = ''
          $ORIGIN ${dom}.
          $TTL 12h

          @ IN SOA ns1.${dom}. hostmaster.${dom}. (
            ${toString config.instance.build-timestamp}
            30m
            2m
            3w
            5m)

          ${optionalString (dom-cfg.default-host != null)
            "@ IN A ${dom-cfg.default-host}"}

          ${mxRecords dom-cfg.mx}

          $TTL 6h

          ${optionalString (dom-cfg.gssapi-realm != null)
            ''_kerberos IN TXT "${dom-cfg.gssapi-realm}"''}

          ${nsRecords dom cfg.nameservers}
          ${join-lines (mapAttrsToList hostRecords cfg.nameservers)}

          ${dmarcRecord dom-cfg.dmarc-report-address}

          ${join-lines
            (mapAttrsToList makeSrvProtocolRecords net-cfg.srv-records)}
          ${join-lines (mapAttrsToList hostRecords net-cfg.hosts)}
          ${join-lines (mapAttrsToList cnameRecord net-cfg.aliases)}
          ${join-lines net-cfg.verbatim-dns-records}
        '';
      }) cfg.domains;
    };
  };
}
