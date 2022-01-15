{ pkgs, ... }:

with pkgs.lib;
let
  join-lines = concatStringsSep "\n";

  pthru = obj: builtins.trace obj obj;

  remove-blank-lines = str:
    concatStringsSep "\n\n"
      (filter builtins.isString
        (builtins.split "\n\n\n+" str));

  n-spaces = n:
    concatStringsSep "" (builtins.genList (_: " ") n);

  pad-to-length = strlen: str: let
    spaces = n-spaces (strlen - (stringLength str));
  in str + spaces;

  record-matcher = builtins.match "^([^;].*) IN ([A-Z][A-Z0-9]*) (.+)$";

  is-record = str: (record-matcher str) != null;

  max-int = foldr (a: b: if (a < b) then b else a) 0;

  make-zone-formatter = zonedata: let
    lines = splitString "\n" zonedata;
    records = filter is-record lines;
    split-records = map record-matcher records;
    index-strlen = i: record: stringLength (elemAt record i);
    record-index-maxlen = i: max-int (map (index-strlen i) split-records);
  in record-formatter (record-index-maxlen 0) (record-index-maxlen 1);

  record-formatter = name-max: type-max: let
    name-padder = pad-to-length name-max;
    type-padder = pad-to-length type-max;
  in record-line: let
    record-parts = record-matcher record-line;
  in
    if (record-parts == null) then
      record-line
    else (let
      name = elemAt record-parts 0;
      type = elemAt record-parts 1;
      data = elemAt record-parts 2;
    in "${name-padder name} IN ${type-padder type} ${data}");

  format-zone = zonedata: let
    formatter = make-zone-formatter zonedata;
    lines = splitString "\n" zonedata;
  in concatStringsSep "\n" (map formatter lines);

  makeSrvRecords = protocol: service: records:
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
  in join-lines (a-record ++
                 aaaa-record ++
                 sshfp-records ++
                 description-record);

  cnameRecord = alias: host: "${alias} IN CNAME ${host}";

  dmarcRecord = dmarc-email:
    optionalString (dmarc-email != null)
      ''_dmarc IN TXT "v=DMARC1;p=quarantine;sp=quarantine;rua=mailto:${dmarc-email};"'';

  mxRecords = mxs: map (mx: "@ IN MX 10 ${mx}.") mxs;

  nsRecords = map (ns-host: "@ IN NS ${ns-host}");

  flatmapAttrsToList = f: attrs:
    foldr (a: b: a ++ b) [] (mapAttrsToList f attrs);


  srvRecordPair = domain: protocol: service: record: {
    "_${service}._${protocol}.${domain}" =
      "${toString record.priority} ${toString record.weight} ${
        toString record.port
      } ${record.host}.";
  };

  domain-records = dom: zone: ''
    $ORIGIN ${dom}.
    $TTL ${zone.default-ttl}

    ${optionalString (zone.default-host != null)
      "@ IN A ${zone.default-host}"}

    ${join-lines (mxRecords zone.mx)}

    ${dmarcRecord zone.dmarc-report-address}

    ${optionalString (zone.gssapi-realm != null)
      ''_kerberos IN TXT "${zone.gssapi-realm}"''}

    ${join-lines (nsRecords zone.nameservers)}

    ${join-lines (mapAttrsToList makeSrvProtocolRecords zone.srv-records)}

    $TTL ${zone.host-record-ttl}

    ${join-lines (mapAttrsToList hostRecords zone.hosts)}

    ${join-lines (mapAttrsToList cnameRecord zone.aliases)}

    ${join-lines zone.verbatim-dns-records}

    ${join-lines (mapAttrsToList
      (subdom: subdomCfg: domain-records "${subdom}.${dom}" subdomCfg)
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

  zoneToZonefile = timestamp: dom: zone:
    remove-blank-lines (format-zone ''
        $ORIGIN ${dom}.
        $TTL ${zone.default-ttl}

        @ IN SOA ns1.${dom}. hostmaster.${dom}. (
            ${toString timestamp}
            30m
            2m
            3w
            5m)

        ${domain-records dom zone}
      '');
}
