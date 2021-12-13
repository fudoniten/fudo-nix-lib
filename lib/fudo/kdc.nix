{ config, lib, pkgs, ... } @ toplevel:

with lib;
let
  cfg = config.fudo.auth.kdc;

  hostname = config.instance.hostname;

  localhost-ips = let
    addr-only = addrinfo: addrinfo.address;
    interface = config.networking.interfaces.lo;
  in
    (map addr-only interface.ipv4.addresses) ++
    (map addr-only interface.ipv6.addresses);

  host-ips =
    (pkgs.lib.fudo.network.host-ips hostname) ++ localhost-ips;

  state-directory = toplevel.config.fudo.auth.kdc.state-directory;

  database-file = "${state-directory}/principals.db";
  iprop-log = "${state-directory}/iprop.log";

  master-server = cfg.master-config != null;
  slave-server = cfg.slave-config != null;

  get-fqdn = hostname:
    "${hostname}.${config.fudo.hosts.${hostname}.domain}";

  kdc-conf = generate-kdc-conf {
    realm = cfg.realm;
    db-file = database-file;
    key-file = cfg.master-key-file;
    acl-data = if master-server then cfg.master-config.acl else null;
  };

  initialize-db =
    { realm, user, group, kdc-conf, key-file, db-name, max-lifetime, max-renewal,
      primary-keytab, kadmin-keytab, kpasswd-keytab, ipropd-keytab, local-hostname }: let

        kadmin-cmd = "kadmin -l -c ${kdc-conf} --";

        get-domain-hosts = domain: let
          host-in-subdomain = host: hostOpts:
            (builtins.match "(.+[.])?${domain}$" hostOpts.domain) != null;
        in attrNames (filterAttrs host-in-subdomain config.fudo.hosts);

        get-host-principals = realm: hostname: let
          host = config.fudo.hosts.${hostname};
        in map (service: "${service}/${hostname}.${host.domain}@${realm}")
          host.kerberos-services;

        add-principal-str = principal:
          "${kadmin-cmd} add --random-key --use-defaults ${principal}";

        test-existence = principal:
          "[[ $( ${kadmin-cmd} get ${principal} ) ]]";

        exists-or-add = principal: ''
          if ${test-existence principal}; then
            echo "skipping ${principal}, already exists"
          else
            ${add-principal-str principal}
          fi
        '';

        ensure-host-principals = realm:
          concatStringsSep "\n"
            (map exists-or-add
              (concatMap (get-host-principals realm)
                (get-domain-hosts (toLower realm))));

        slave-hostnames = map get-fqdn cfg.master-config.slave-hosts;

        ensure-iprop-principals = concatStringsSep "\n"
          (map (host: exists-or-add "iprop/${host}@${realm}")
            [ local-hostname ] ++ slave-hostnames);

        copy-slave-principals-file = let
          slave-principals = map
            (host: "iprop/${hostname}@${cfg.realm}")
            slave-hostnames;
          slave-principals-file = pkgs.writeText "heimdal-slave-principals"
            (concatStringsSep "\n" slave-principals);
        in optionalString (slave-principals-file != null) ''
          cp ${slave-principals-file} ${state-directory}/slaves
          # Since it's copied from /nix/store, this is by default read-only,
          # which causes updates to fail.
          chmod u+w ${state-directory}/slaves
        '';

      in pkgs.writeShellScript "initialize-kdc-db.sh" ''
           TMP=$(mktemp -d -t kdc-XXXXXXXX)
           if [ ! -e ${database-file} ]; then
             ## CHANGING HOW THIS WORKS
             ## Now we expect the key to be provided
             # kstash --key-file=${key-file} --random-key
             ${kadmin-cmd} init --realm-max-ticket-life="${max-lifetime}" --realm-max-renewable-life="${max-renewal}" ${realm}
           fi

           ${ensure-host-principals realm}

           ${ensure-iprop-principals}

           echo "*** BEGIN EXTRACTING KEYTABS"
           echo "***   You can probably ignore the 'principal does not exist' errors that follow,"
           echo "***   they're just testing for principal existence before creating those that"
           echo "***   don't already exist"

           ${kadmin-cmd} ext_keytab --keytab=$TMP/primary.keytab */${local-hostname}@${realm}
           mv $TMP/primary.keytab ${primary-keytab}
           ${kadmin-cmd} ext_keytab --keytab=$TMP/kadmin.keytab kadmin/admin@${realm}
           mv $TMP/kadmin.keytab ${kadmin-keytab}
           ${kadmin-cmd} ext_keytab --keytab=$TMP/kpasswd.keytab kadmin/changepw@${realm}
           mv $TMP/kpasswd.keytab ${kpasswd-keytab}
           ${kadmin-cmd} ext_keytab --keytab=$TMP/ipropd.keytab iprop/${local-hostname}@${realm}
           mv $TMP/ipropd.keytab ${ipropd-keytab}

           echo "*** END EXTRACTING KEYTABS"

           ${copy-slave-principals-file}
         '';

  generate-kdc-conf = { realm, db-file, key-file, acl-data  }:
    pkgs.writeText "kdc.conf" ''
      [kdc]
        database = {
          dbname = sqlite:${db-file}
          realm = ${realm}
          mkey_file = ${key-file}
          ${optionalString (acl-data != null)
            "acl_file = ${generate-acl-file acl-data}"}
          log_file = ${iprop-log}
        }

      [realms]
        ${realm} = {
          enable-http = false
        }

      [logging]
        kdc = FILE:${state-directory}/kerberos.log
        default = FILE:${state-directory}/kerberos.log
    '';

  aclEntry = { principal, ... }: {
    options = with types; {
      perms = let
        perms = [
          "change-password"
          "add"
          "list"
          "delete"
          "modify"
          "get"
          "get-keys"
          "all"
        ];
      in mkOption {
        type = listOf (enum perms);
        description = "List of permissions.";
        default = [ ];
      };

      target = mkOption {
        type = nullOr str;
        description = "Target principals.";
        default = null;
        example = "hosts/*@REALM.COM";
      };
    };
  };

  generate-acl-file = acl-entries: let
    perms-to-permstring = perms: concatStringsSep "," perms;
  in
    pkgs.writeText "kdc.acl" (concatStringsSep "\n" (mapAttrsToList
      (principal: opts:
        "${principal} ${perms-to-permstring opts.perms}${
          optionalString (opts.target != null) " ${opts.target}" }")
      acl-entries));

  kadmin-local = kdc-conf:
    pkgs.writeShellScriptBin "kadmin.local" ''
      ${pkgs.heimdalFull}/bin/kadmin -l -c ${kdc-conf} $@
    '';

  masterOpts = { ... }: {
    options = with types; {
      acl = mkOption {
        type = attrsOf (submodule aclEntry);
        description = "Mapping of pricipals to a list of permissions.";
        default = { "*/admin" = [ "all" ]; };
        example = {
          "*/root" = [ "all" ];
          "admin-user" = [ "add" "list" "modify" ];
        };
      };

      kadmin-keytab = mkOption {
        type = str;
        description = "Location at which to store keytab for kadmind.";
        default = "${state-directory}/kadmind.keytab";
      };

      kpasswdd-keytab = mkOption {
        type = str;
        description = "Location at which to store keytab for kpasswdd.";
        default = "${state-directory}/kpasswdd.keytab";
      };

      ipropd-keytab = mkOption {
        type = str;
        description = "Location at which to store keytab for ipropd master.";
        default = "${state-directory}/ipropd.keytab";
      };

      slave-hosts = mkOption {
        type = listOf str;
        description = ''
          A list of host to which the database should be propagated.

          Must exist in the Fudo Host database.
        '';
        default = [ ];
      };
    };
  };

  slaveOpts = { ... }: {
    options = with types; {
      master-host = mkOption {
        type = str;
        description = ''
          Host from which to recieve database updates.

          Must exist in the Fudo Host database.
        '';
      };

      ipropd-keytab = mkOption {
        type = nullOr str;
        description = "Location at which to find keytab for ipropd slave.";
      };
    };
  };

in {

  options.fudo.auth.kdc = with types; {
    enable = mkEnableOption "Fudo KDC";

    realm = mkOption {
      type = str;
      description = "The realm for which we are the acting KDC.";
    };

    bind-addresses = mkOption {
      type = listOf str;
      description = "A list of IP addresses on which to bind.";
      default = host-ips;
    };

    user = mkOption {
      type = str;
      description = "User as which to run Heimdal servers.";
      default = "kerberos";
    };

    group = mkOption {
      type = str;
      description = "Group as which to run Heimdal servers.";
      default = "kerberos";
    };

    state-directory = mkOption {
      type = str;
      description = "Path at which to store kerberos database.";
      default = "/var/lib/kerberos";
    };

    master-key-file = mkOption {
      type = str;
      description = ''
        File containing the master key for the realm.

        Must be provided!
      '';
    };

    primary-keytab = mkOption {
      type = str;
      description = "Location of host master keytab.";
      default = "${state-directory}/host.keytab";
    };

    master-config = mkOption {
      type = nullOr (submodule masterOpts);
      description = "Configuration for the master KDC server.";
      default = null;
    };

    slave-config = mkOption {
      type = nullOr (submodule slaveOpts);
      description = "Configuration for slave KDC servers.";
      default = null;
    };

    max-ticket-lifetime = mkOption {
      type = str;
      description = "Maximum lifetime of a single ticket in this realm.";
      default = "1d";
    };

    max-ticket-renewal = mkOption {
      type = str;
      description = "Maximum time a ticket may be renewed in this realm.";
      default = "7d";
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = master-server || slave-server;
        message =
          "For the KDC to be enabled, a master OR slave config must be provided.";
      }
      {
        assertion = !(master-server && slave-server);
        message =
          "Only one of master-config and slave-config may be provided.";
      }
    ];

    users = {
      users.${cfg.user} = {
        isSystemUser = true;
        home = state-directory;
        group = cfg.group;
      };

      groups.${cfg.group} = { members = [ cfg.user ]; };
    };

    krb5 = {
      libdefaults = {
        # Stick to ~/.k5login
        # k5login_directory = cfg.k5login-directory;
        ticket_lifetime = cfg.max-ticket-lifetime;
        renew_lifetime = cfg.max-ticket-renewal;
      };
      # Sorry, port 80 isn't available!
      realms.${cfg.realm}.enable-http = false;
      extraConfig = ''
        default = FILE:${state-directory}/kerberos.log
      '';
    };

    environment = {
      systemPackages = [ pkgs.heimdalFull (kadmin-local kdc-conf) ];

      ## This shouldn't be necessary...every host gets a krb5.keytab
      # etc = {
      #   "krb5.keytab" = {
      #     user = "root";
      #     group = "root";
      #     mode = "0400";
      #     source = cfg.primary-keytab;
      #   };
      # };
    };

    systemd.tmpfiles.rules = [
      "d ${state-directory} 0740 ${cfg.user} ${cfg.group} - -"
    ];

    fudo.system = {
      services = if master-server then {

        heimdal-kdc = let
          listen-addrs = concatStringsSep " "
            (map (addr: "--addresses=${addr}") cfg.bind-addresses);
        in {
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          description =
            "Heimdal Kerberos Key Distribution Center (ticket server).";
          execStart = "${pkgs.heimdalFull}/libexec/heimdal/kdc -c ${kdc-conf} --ports=88 ${listen-addrs}";
          user = cfg.user;
          group = cfg.group;
          workingDirectory = state-directory;
          privateNetwork = false;
          addressFamilies = [ "AF_INET" "AF_INET6" ];
          requiredCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          environment = { KRB5_CONFIG = "/etc/krb5.conf"; };
        };

        heimdal-kdc-init = let
          init-cmd = initialize-db {
            realm = cfg.realm;
            user = cfg.user;
            group = cfg.group;
            kdc-conf = kdc-conf;
            key-file = cfg.master-key-file;
            db-name = database-file;
            max-lifetime = cfg.max-ticket-lifetime;
            max-renewal = cfg.max-ticket-renewal;
            primary-keytab = cfg.primary-keytab;
            kadmin-keytab = cfg.master-config.kadmin-keytab;
            kpasswd-keytab = cfg.master-config.kpasswdd-keytab;
            ipropd-keytab = cfg.master-config.ipropd-keytab;
            local-hostname =
              "${config.instance.hostname}.${config.instance.local-domain}";
          };
        in {
          requires = [ "heimdal-kdc.service" ];
          wantedBy = [ "multi-user.target" ];
          description = "Initialization script for Heimdal KDC.";
          type = "oneshot";
          execStart = "${init-cmd}";
          user = cfg.user;
          group = cfg.group;
          path = with pkgs; [ heimdalFull ];
          protectSystem = "full";
          addressFamilies = [ "AF_INET" "AF_INET6" ];
          workingDirectory = state-directory;
          environment = { KRB5_CONFIG = "/etc/krb5.conf"; };
        };

        heimdal-ipropd-master = mkIf (length cfg.master-config.slave-hosts > 0) {
          requires = [ "heimdal-kdc.service" ];
          wantedBy = [ "multi-user.target" ];
          description = "Propagate changes to the master KDC DB to all slaves.";
          path = with pkgs; [ heimdalFull ];
          execStart = "${pkgs.heimdalFull}/libexec/heimdal/ipropd-master -c ${kdc-conf} -k ${cfg.master.ipropd-keytab}";
          user = cfg.user;
          group = cfg.group;
          workingDirectory = state-directory;
          privateNetwork = false;
          addressFamilies = [ "AF_INET" "AF_INET6" ];
          environment = { KRB5_CONFIG = "/etc/krb5.conf"; };
        };

      } else {

        heimdal-kdc-slave = let
          listen-addrs = concatStringsSep " "
            (map (addr: "--addresses=${addr}") cfg.bind-addresses);
          command =
            "${pkgs.heimdalFull}/libexec/heimdal/kdc -c ${kdc-conf} --ports=88 ${listen-addrs}";
        in {
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          description =
            "Heimdal Slave Kerberos Key Distribution Center (ticket server).";
          execStart = command;
          user = cfg.user;
          group = cfg.group;
          workingDirectory = state-directory;
          privateNetwork = false;
          addressFamilies = [ "AF_INET" "AF_INET6" ];
          requiredCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          environment = { KRB5_CONFIG = "/etc/krb5.conf"; };
        };

        heimdal-ipropd-slave = {
          wantedBy = [ "multi-user.target" ];
          description = "Receive changes propagated from the KDC master server.";
          path = with pkgs; [ heimdalFull ];
          execStart = concatStringsSep " " [
            "${pkgs.heimdalFull}/libexec/heimdal/ipropd-slave"
            "--config-file=${kdc-conf}"
            "--keytab=${cfg.slave-config.ipropd-keytab}"
            "--realm=${cfg.realm}"
            "--hostname=${get-fqdn hostname}"
            "--port=2121"
            "--verbose"
            (get-fqdn cfg.slave-config.master-host)
          ];
          user = cfg.user;
          group = cfg.group;
          workingDirectory = state-directory;
          privateNetwork = false;
          addressFamilies = [ "AF_INET" "AF_INET6" ];
          requiredCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          environment = { KRB5_CONFIG = "/etc/krb5.conf"; };
        };
      };
    };

    services.xinetd = mkIf master-server {
      enable = true;

      services = [
        {
          name = "kerberos-adm";
          user = cfg.user;
          server = "${pkgs.heimdalFull}/libexec/heimdal/kadmind";
          protocol = "tcp";
          serverArgs =
            "--config-file=${kdc-conf} --keytab=${cfg.master-config.kadmin-keytab}";
        }
        {
          name = "kpasswd";
          user = cfg.user;
          server = "${pkgs.heimdalFull}/libexec/heimdal/kpasswdd";
          protocol = "udp";
          serverArgs =
            "--config-file=${kdc-conf} --keytab=${cfg.master-config.kpasswdd-keytab}";
        }
      ];
    };

    networking = {
      firewall = {
        allowedTCPPorts = [ 88 ] ++
                          (optionals master-server [ 749 ]) ++
                          (optionals slave-server [ 2121 ]);
        allowedUDPPorts = [ 88 ] ++
                          (optionals master-server [ 464 ]) ++
                          (optionals slave-server [ 2121 ]);
      };
    };
  };
}
