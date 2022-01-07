{ pkgs, ... }:

with pkgs.lib;
let
  join-lines = concatStringsSep "\n";

  dump = obj: builtins.trace obj obj;

  makeSrvRecords = protocol: service: records: let
    service-blah = (dump service);
    record-blah = (dump records);
    in
    join-lines (map (record:
      "_${service}._${protocol} IN SRV ${toString record.priority} ${
        toString record.weight
      } ${toString record.port} ${record.host}.") records);

  makeSrvProtocolRecords = protocol: services:
    join-lines (mapAttrsToList (makeSrvRecords protocol) services);

  srvRecordOpts = with types; {
    options = {
      weight = mkOption {
        type = int;
        description = "Weight relative to other records.";
        default = 1;
      };

      priority = mkOption {
        type = int;
        description = "Priority to give this record.";
        default = 0;
      };

      port = mkOption {
        type = port;
        description = "Port to use when connecting.";
      };

      host = mkOption {
        type = str;
        description = "Host to contact for this service.";
        example = "my-host.my-domain.com.";
      };
    };
  };

  hostRecords = hostname: nethost-data: let
    sshfp-records = map (sshfp: "${hostname} IN SSHFP ${sshfp}")
      nethost-data.sshfp-records;
    a-record = optional (nethost-data.ipv4-address != null)
      "${hostname} IN A ${nethost-data.ipv4-address}";
    aaaa-record = optional (nethost-data.ipv6-address != null)
      "${hostname} IN AAAA ${nethost-data.ipv6-address}";
    description-record = optional (nethost-data.description != null)
      ''${hostname} IN TXT "${nethost-data.description}"'';
  in
    join-lines (a-record ++ aaaa-record ++ description-record ++ sshfp-records);

  cnameRecord = alias: host: "${alias} IN CNAME ${host}";

  dmarcRecord = dmarc-email:
    optionalString (dmarc-email != null)
      ''_dmarc IN TXT "v=DMARC1;p=quarantine;sp=quarantine;rua=mailto:${dmarc-email};"'';

  mxRecords = mxs: map (mx: "@ IN MX 10 ${mx}.") mxs;

  nsRecords = domain: ns-hosts:
    mapAttrsToList (host: _: "@ IN NS ${host}.${domain}.") ns-hosts;

  flatmapAttrsToList = f: attrs:
    foldr (a: b: a ++ b) [] (mapAttrsToList f attrs);

  nsARecords = _: ns-hosts: let
    a-record = host: hostOpts: optional (hostOpts.ipv4-address != null)
      "${host} IN A ${hostOpts.ipv4-address}";
    aaaa-record = host: hostOpts: optional (hostOpts.ipv6-address != null)
      "${host} IN AAAA ${hostOpts.ipv6-address}";
    description-record = host: hostOpts: optional (hostOpts.description != null)
      ''${host} IN TXT "${hostOpts.description}"'';
  in flatmapAttrsToList
    (host: hostOpts:
      (a-record host hostOpts) ++
      (aaaa-record host hostOpts) ++
      (description-record host hostOpts))
    ns-hosts;


  srvRecordPair = domain: protocol: service: record: {
    "_${service}._${protocol}.${domain}" =
      "${toString record.priority} ${toString record.weight} ${
        toString record.port
      } ${record.host}.";
  };

  domain-record = dom: zone: ''
    $ORIGIN ${dom}.
    $TTL ${zone.default-ttl}

    ###
    # Default Host
    ###
    ${optionalString (zone.default-host != null)
      "@ IN A ${zone.default-host}"}

    ###
    # MX Records
    ###
    ${join-lines (mxRecords zone.mx)}

    # dmarc
    ${dmarcRecord zone.dmarc-report-address}

    ###
    # Kerberos Realm
    ###
    ${optionalString (zone.gssapi-realm != null)
      ''_kerberos IN TXT "${zone.gssapi-realm}"''}

    ###
    # Nameservers
    ###
    ${join-lines (nsRecords dom zone.nameservers)}

    ${join-lines (nsARecords dom zone.nameservers)}

    ###
    # General Records
    ###
    $TTL ${zone.host-record-ttl}

    ###
    # SRV Records
    ###
    ${join-lines (mapAttrsToList makeSrvProtocolRecords zone.srv-records)}

    ###
    # Host Records
    ###
    ${join-lines (mapAttrsToList hostRecords zone.hosts)}

    ###
    # CNAMEs
    ###
    ${join-lines (mapAttrsToList cnameRecord zone.aliases)}

    ###
    # Verbatim Records
    ###
    ${join-lines zone.verbatim-dns-records}

    ###
    # Subdomains of ${dom}
    ###
    ${join-lines (mapAttrsToList
      (subdom: subdomCfg: subdomain-record "${subdom}.${dom}" subdomCfg)
      zone.subdomains)}
  '';

in rec {

  srvRecords = with types; attrsOf (attrsOf (listOf (submodule srvRecordOpts)));

  srvRecordsToBindZone = srvRecords:
    join-lines (mapAttrsToList makeSrvProtocolRecords srvRecords);

  concatMapAttrs = f: attrs:
    concatMap (x: x) (mapAttrsToList (key: val: f key val) attrs);

  srvRecordsToPairs = domain: srvRecords: 
    listToAttrs (concatMapAttrs (protocol: services:
      concatMapAttrs
      (service: records: map (srvRecordPair domain protocol service) records) services)
      srvRecords);

  zoneToZonefile = timestamp: dom: zone: ''
    $ORIGIN ${dom}.
    $TTL ${zone.default-ttl}

    @ IN SOA ns1.${dom}. hostmaster.${dom}. (
      ${toString timestamp}
      30m
      2m
      3w
      5m)

    ${domain-record dom zone}
  '';
}
