{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;
  domain = config.instance.local-domain;
  cfg = config.fudo.domains.${domain};

in {
  config = let
    hostname = config.instance.hostname;
    is-master = hostname == cfg.kerberos-master;
    is-slave = elem hostname cfg.kerberos-slaves;

    kerberized-domain = cfg.kerberos-master != null;

  in {
    fudo = {
      auth.kdc = mkIf (is-master || is-slave) {
        enable = true;
        realm = cfg.gssapi-realm;
        # TODO: Also bind to ::1?
        bind-addresses =
          (pkgs.lib.fudo.network.host-ips config hostname) ++
          [ "127.0.0.1" ] ++ (optional config.networking.enableIPv6 "::1");
        master-config = mkIf is-master {
          acl = let
            admin-entries = genAttrs cfg.local-admins
              (admin: {
                perms = [ "add" "change-password" "list" ];
              });
          in admin-entries // {
            "*/root" = { perms = [ "all" ]; };
          };
        };
        slave-config = mkIf is-slave {
          master-host = cfg.kerberos-master;
          # You gotta provide the keytab yourself, sorry...
        };
      };

      dns.domains.${domain} = {
        network-definition = mkIf kerberized-domain {
          srv-records = let
            get-fqdn = hostname:
              "${hostname}.${config.fudo.hosts.${hostname}.domain}";

            create-srv-record = port: hostname: {
              port = port;
              host = hostname;
            };

            all-servers = map get-fqdn
              ([cfg.kerberos-master] ++ cfg.kerberos-slaves);

            master-servers =
              map get-fqdn [cfg.kerberos-master];

          in {
            tcp = {
              kerberos = map (create-srv-record 88) all-servers;
              kerberos-adm = map (create-srv-record 749) master-servers;
            };
            udp = {
              kerberos = map (create-srv-record 88) all-servers;
              kerberos-master = map (create-srv-record 88) master-servers;
              kpasswd = map (create-srv-record 464) master-servers;
            };
          };
        };
      };
    };
  };
}
