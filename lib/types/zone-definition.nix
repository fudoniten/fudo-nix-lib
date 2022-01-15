{ lib, ... }:

with lib;
let
  srvRecordOpts = { ... }: {
    options = with types; {
      priority = mkOption {
        type = int;
        description = "Priority to give to this record.";
        default = 0;
      };

      weight = mkOption {
        type = int;
        description =
          "Weight to give this record, among records of equivalent priority.";
        default = 5;
      };

      port = mkOption {
        type = port;
        description = "Port for service on this host.";
        example = 88;
      };

      host = mkOption {
        type = str;
        description = "Host providing service.";
        example = "my-host.my-domain.com";
      };
    };
  };

  networkHostOpts = import ./network-host.nix { inherit lib; };

  zoneOpts = {
    options = with types; {
      hosts = mkOption {
        type = attrsOf (submodule networkHostOpts);
        description = "Hosts on the local network, with relevant settings.";
        example = {
          my-host = {
            ipv4-address = "192.168.0.1";
            mac-address = "aa:aa:aa:aa:aa";
          };
        };
        default = { };
      };

      nameservers = mkOption {
        type = listOf str;
        description = "List of zone nameservers.";
        example = [
          "ns1.fudo.org."
          "10.0.0.1"
        ];
        default = [];
      };

      srv-records = mkOption {
        type = attrsOf (attrsOf (listOf (submodule srvRecordOpts)));
        description = "SRV records for the network.";
        example = {
          tcp = {
            kerberos = [
              {
                port = 88;
                host = "krb-host.my-domain.com";
              }
              {
                port = 88;
                host = "krb-host2.my-domain.com";
              }
            ];
          };
        };
        default = { };
      };

      metric-records = mkOption {
        type = attrsOf (listOf (submodule srvRecordOpts));
        description = "Map of metric type to list of SRV host records.";
        example = {
          node = [
            {
              host = "my-host.my-domain.com";
              port = 443;
            }
            {
              host = "my-host2.my-domain.com";
              port = 443;
            }
          ];
          rspamd = [
            {
              host = "mail-host.my-domain.com";
              port = 443;
            }
          ];
        };
        default = { };
      };

      aliases = mkOption {
        type = attrsOf str;
        default = { };
        description =
          "A mapping of host-alias -> hostnames to add to the domain record.";
        example = {
          mail = "my-mail-host";
          music = "musicall-host.other-domain.com.";
        };
      };

      verbatim-dns-records = mkOption {
        type = listOf str;
        description = "Records to be inserted verbatim into the DNS zone.";
        example = [ "some-host IN CNAME base-host" ];
        default = [ ];
      };

      dmarc-report-address = mkOption {
        type = nullOr str;
        description = "The email to use to recieve DMARC reports, if any.";
        example = "admin-user@domain.com";
        default = null;
      };

      default-host = mkOption {
        type = nullOr str;
        description =
          "IP of the host which will act as the default server for this domain, if any.";
        default = null;
      };

      mx = mkOption {
        type = listOf str;
        description = "A list of mail servers serving this domain.";
        default = [ ];
      };

      gssapi-realm = mkOption {
        type = nullOr str;
        description = "Kerberos GSSAPI realm of the zone.";
        default = null;
      };

      default-ttl = mkOption {
        type = str;
        description = "Default time-to-live for this zone.";
        default = "3h";
      };

      host-record-ttl = mkOption {
        type = str;
        description = "Default time-to-live for records in this zone";
        default = "1h";
      };

      description = mkOption {
        type = str;
        description = "Description of this zone.";
      };

      subdomains = mkOption {
        type = attrsOf (submodule zoneOpts);
        description = "Subdomains of the current zone.";
        default = {};
      };
    };
  };

in zoneOpts
