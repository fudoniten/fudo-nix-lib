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

  srvRecordPair = domain: protocol: service: record: {
    "_${service}._${protocol}.${domain}" =
      "${toString record.priority} ${toString record.weight} ${
        toString record.port
      } ${record.host}.";
  };

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
}
