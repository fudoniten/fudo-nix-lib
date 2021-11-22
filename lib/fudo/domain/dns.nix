{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;
  domain = config.instance.local-domain;
  cfg = config.fudo.domains.${domain};

  served-domain = cfg.primary-nameserver != null;

  is-primary = hostname == cfg.primary-nameserver;

  create-srv-record = port: hostname: {
    port = port;
    host = hostname;
  };

in {
  config = {
    fudo.dns = mkIf is-primary (let
      primary-ip = pkgs.lib.fudo.network.host-ipv4 config hostname;
      all-ips = pkgs.lib.fudo.network.host-ips config hostname;
    in {
      enable = true;
      identity = "${hostname}.${domain}";
      nameservers = {
        ns1 = {
          ipv4-address = primary-ip;
          description = "Primary ${domain} nameserver";
        };
      };

      # Deliberately leaving out localhost so the primary nameserver
      # can use a custom recursor
      listen-ips = all-ips;

      domains = {
        ${domain} = {
          dnssec = true;
          default-host = primary-ip;
          gssapi-realm = cfg.gssapi-realm;
          mx = optional (cfg.primary-mailserver != null)
            cfg.primary-mailserver;
          # TODO: there's no guarantee this exists...
          dmarc-report-address = "dmarc-report@${domain}";

          network-definition = let
            network = config.fudo.networks.${domain};
          in network // {
            srv-records = {
              tcp = {
                domain = [{
                  host = "ns1.${domain}";
                  port = 53;
                }];
              };
              udp = {
                domain = [{
                  host = "ns1.${domain}";
                  port = 53;
                }];
              };
            };
          };
        };
      };
    });
  };
}
