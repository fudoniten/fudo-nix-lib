{ config, pkgs, lib, ... }:

with lib;
let
  backplane-cfg = config.fudo.backplane;

  cfg = backplane-cfg.dns;

  powerdns-conf-dir = "${cfg.powerdns.home}/conf.d";

in {
  config = mkIf cfg.enable {
    users = {
      users = {
        "${cfg.user}" = {
          isSystemUser = true;
          group = cfg.group;
          createHome = true;
          home = "/var/home/${cfg.user}";
        };
        ${cfg.powerdns.user} = {
          isSystemUser = true;
          home = cfg.powerdns.home;
          createHome = true;
        };
      };

      groups = {
        ${cfg.group} = { members = [ cfg.user ]; };
        ${cfg.powerdns.user} = { members = [ cfg.powerdns.user ]; };
      };
    };

    fudo = {
      system.services = {
        backplane-powerdns-config-generator = {
          description =
            "Generate postgres configuration for backplane DNS server.";
          requires = cfg.required-services;
          type = "oneshot";
          restartIfChanged = true;
          partOf = [ "backplane-dns.target" ];

          readWritePaths = [ powerdns-conf-dir ];

          # This builds the config in a bash script, to avoid storing the password
          # in the nix store at any point
          script = let
            user = cfg.powerdns.user;
            db = cfg.powerdns.database;
          in ''
            TMPDIR=$(${pkgs.coreutils}/bin/mktemp -d -t pdns-XXXXXXXXXX)
            TMPCONF=$TMPDIR/pdns.local.gpgsql.conf

            if [ ! -f ${cfg.database.password-file} ]; then
              echo "${cfg.database.password-file} does not exist!"
              exit 1
            fi

            touch $TMPCONF
            chmod go-rwx $TMPCONF
            chown ${user} $TMPCONF
            PASSWORD=$(cat ${db.password-file})
            echo "launch+=gpgsql" >> $TMPCONF
            echo "gpgsql-host=${db.host}" >> $TMPCONF
            echo "gpgsql-dbname=${db.database}" >> $TMPCONF
            echo "gpgsql-user=${db.username}" >> $TMPCONF
            echo "gpgsql-password=$PASSWORD" >> $TMPCONF
            echo "gpgsql-dnssec=yes" >> $TMPCONF

            mv $TMPCONF ${powerdns-conf-dir}/pdns.local.gpgsql.conf
            rm -rf $TMPDIR

            exit 0
          '';
        };

        backplane-dns = {
          description = "Fudo DNS Backplane Server";
          restartIfChanged = true;
          path = with pkgs; [ backplane-dns-server ];
          execStart = "launch-backplane-dns.sh";
          pidFile = "/run/backplane-dns.$USERNAME.pid";
          user = cfg.user;
          group = cfg.group;
          partOf = [ "backplane-dns.target" ];
          requires = cfg.required-services ++ [ "postgresql.service" ];
          environment = {
            FUDO_DNS_BACKPLANE_XMPP_HOSTNAME = backplane-cfg.backplane-host;
            FUDO_DNS_BACKPLANE_XMPP_USERNAME = cfg.backplane-role.role;
            FUDO_DNS_BACKPLANE_XMPP_PASSWORD_FILE = cfg.backplane-role.password-file;
            FUDO_DNS_BACKPLANE_DATABASE_HOSTNAME = cfg.database.host;
            FUDO_DNS_BACKPLANE_DATABASE_NAME = cfg.database.database;
            FUDO_DNS_BACKPLANE_DATABASE_USERNAME =
              cfg.database.username;
            FUDO_DNS_BACKPLANE_DATABASE_PASSWORD_FILE =
              cfg.database.password-file;

            CL_SOURCE_REGISTRY =
              pkgs.lib.fudo.lisp.lisp-source-registry pkgs.backplane-dns-server;
          };
        };
      };
    };

    systemd = {
      tmpfiles.rules = [
        "d ${powerdns-conf-dir} 0700 ${cfg.powerdns.user} - - -"
      ];

      targets = {
        backplane-dns = {
          description = "Fudo DNS backplane services.";
          wantedBy = [ "multi-user.target" ];
          after = cfg.required-services ++ [ "postgresql.service" ];
        };
      };

      services = {
        backplane-powerdns = let
          pdns-config-dir = pkgs.writeTextDir "pdns.conf" ''
            local-address=${lib.concatStringsSep ", " cfg.listen-v4-addresses}
            local-ipv6=${lib.concatStringsSep ", " cfg.listen-v6-addresses}
            local-port=${toString cfg.port}
            launch=
            include-dir=${powerdns-conf-dir}/
          '';
        in {
          description = "Backplane PowerDNS name server";
          requires = [
            "postgresql.service"
            "backplane-powerdns-config-generator.service"
          ];
          after = [ "network.target" ];
          path = with pkgs; [ powerdns postgresql ];
          serviceConfig = {
            ExecStart = "pdns_server --setuid=${cfg.powerdns.user} --setgid=${cfg.powerdns.user} --chroot=${cfg.powerdns.home} --socket-dir=/ --daemon=no --guardian=no --disable-syslog --write-pid=no --config-dir=${pdns-config-dir}";
          };
        };
      };
    };
  };
}
