{ config, lib, pkgs, ... }:

with lib;
let

  cfg = config.fudo.auth.ldap-server;

  user-type = import ../types/user.nix { inherit lib; };

  stringJoin = concatStringsSep;

  getUserGidNumber = user: group-map: group-map.${user.primary-group}.gid;

  attrOr = attrs: attr: value: if attrs ? ${attr} then attrs.${attr} else value;

  ca-path = "${cfg.state-directory}/ca.pem";

  build-ca-script = target: ca-cert: site-chain: let
    user = config.services.openldap.user;
    group = config.services.openldap.group;
  in pkgs.writeShellScript "build-openldap-ca-script.sh" ''
    cat ${site-chain} ${ca-cert} > ${target}
    chmod 440 ${target}
    chown ${user}:${group} ${target}
  '';

  mkHomeDir = username: user-opts:
    if (user-opts.primary-group == "admin") then
      "/home/${username}"
    else
      "/home/${user-opts.primary-group}/${username}";

  userLdif = base: name: group-map: opts: ''
    dn: uid=${name},ou=members,${base}
    uid: ${name}
    objectClass: account
    objectClass: shadowAccount
    objectClass: posixAccount
    cn: ${opts.common-name}
    uidNumber: ${toString (opts.uid)}
    gidNumber: ${toString (getUserGidNumber opts group-map)}
    homeDirectory: ${mkHomeDir name opts}
    description: ${opts.description}
    shadowLastChange: 12230
    shadowMax: 99999
    shadowWarning: 7
    userPassword: ${opts.ldap-hashed-passwd}
  '';

  systemUserLdif = base: name: opts: ''
    dn: cn=${name},${base}
    objectClass: organizationalRole
    objectClass: simpleSecurityObject
    cn: ${name}
    description: ${opts.description}
    userPassword: ${opts.ldap-hashed-password}
  '';

  toMemberList = userList:
    stringJoin "\n" (map (username: "memberUid: ${username}") userList);

  groupLdif = base: name: opts: ''
    dn: cn=${name},ou=groups,${base}
    objectClass: posixGroup
    cn: ${name}
    gidNumber: ${toString (opts.gid)}
    description: ${opts.description}
    ${toMemberList opts.members}
  '';

  systemUsersLdif = base: user-map:
    stringJoin "\n"
    (mapAttrsToList (name: opts: systemUserLdif base name opts) user-map);

  groupsLdif = base: group-map:
    stringJoin "\n"
    (mapAttrsToList (name: opts: groupLdif base name opts) group-map);

  usersLdif = base: group-map: user-map:
    stringJoin "\n"
      (mapAttrsToList (name: opts: userLdif base name group-map opts) user-map);

in {

  options = with types; {
    fudo = {
      auth = {
        ldap-server = {
          enable = mkEnableOption "Fudo Authentication";

          kerberos-host = mkOption {
            type = str;
            description = ''
              The name of the host to use for Kerberos authentication.
            '';
          };

          kerberos-keytab = mkOption {
            type = str;
            description = ''
              The path to a keytab for the LDAP server, containing a principal for ldap/<hostname>.
            '';
          };

          ssl-certificate = mkOption {
            type = str;
            description = ''
              The path to the SSL certificate to use for the server.
            '';
          };

          ssl-chain = mkOption {
            type = str;
            description = ''
              The path to the SSL chain to to the certificate for the server.
            '';
          };

          ssl-private-key = mkOption {
            type = str;
            description = ''
              The path to the SSL key to use for the server.
            '';
          };

          ssl-ca-certificate = mkOption {
            type = nullOr str;
            description = ''
              The path to the SSL CA cert used to sign the certificate.
            '';
            default = null;
          };

          organization = mkOption {
            type = str;
            description = ''
              The name to use for the organization.
            '';
          };

          base = mkOption {
            type = str;
            description = "The base dn of the LDAP server.";
            example = "dc=fudo,dc=org";
          };

          rootpw-file = mkOption {
            default = "";
            type = str;
            description = ''
              The path to a file containing the root password for this database.
            '';
          };

          listen-uris = mkOption {
            type = listOf str;
            description = ''
              A list of URIs on which the ldap server should listen.
            '';
            example = [ "ldap://auth.fudo.org" "ldaps://auth.fudo.org" ];
          };

          users = mkOption {
            type = attrsOf (submodule user-type.userOpts);
            example = {
              tester = {
                uid = 10099;
                common-name = "Joe Blow";
                hashed-password = "<insert password hash>";
              };
            };
            description = ''
              Users to be added to the Fudo LDAP database.
            '';
            default = { };
          };

          groups = mkOption {
            default = { };
            type = attrsOf (submodule user-type.groupOpts);
            example = {
              admin = {
                gid = 1099;
                members = [ "tester" ];
              };
            };
            description = ''
              Groups to be added to the Fudo LDAP database.
            '';
          };

          system-users = mkOption {
            default = { };
            type = attrsOf (submodule user-type.systemUserOpts);
            example = {
              replicator = {
                description = "System user for database sync";
                ldap-hashed-password = "<insert password hash>";
              };
            };
            description = "System users to be added to the Fudo LDAP database.";
          };

          state-directory = mkOption {
            type = str;
            description = "Path at which to store openldap database & state.";
          };

          systemd-target = mkOption {
            type = str;
            description = "Systemd target for running ldap server.";
            default = "fudo-ldap-server.target";
          };

          required-services = mkOption {
            type = listOf str;
            description = "Systemd services on which the server depends.";
            default = [ ];
          };
        };
      };
    };
  };

  config = mkIf cfg.enable {

    environment = {
      etc = {
        "openldap/sasl2/slapd.conf" = {
          mode = "0400";
          user = config.services.openldap.user;
          group = config.services.openldap.group;
          text = ''
            mech_list: gssapi external
            keytab: ${cfg.kerberos-keytab}
          '';
        };
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ 389 636 ];
      allowedUDPPorts = [ 389 ];
    };

    systemd = {
      tmpfiles.rules = let
        ca-dir = dirOf ca-path;
        user = config.services.openldap.user;
        group = config.services.openldap.group;
      in [
        "d ${ca-dir} 0700 ${user} ${group} - -"
      ];

      services.openldap = {
        partOf = [ cfg.systemd-target ];
        requires = cfg.required-services;
        environment.KRB5_KTNAME = cfg.kerberos-keytab;
        preStart = mkBefore
          "${build-ca-script ca-path
            cfg.ssl-chain
            cfg.ssl-ca-certificate}";
        serviceConfig = {
          PrivateDevices = true;
          PrivateTmp = true;
          PrivateMounts = true;
          ProtectControlGroups = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectSystem = true;
          ProtectHostname = true;
          ProtectHome = true;
          ProtectClock = true;
          ProtectKernelLogs = true;
          KeyringMode = "private";
          # RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          Restart = "on-failure";
          LockPersonality = true;
          RestrictRealtime = true;
          MemoryDenyWriteExecute = true;
          SystemCallFilter = concatStringsSep " " [
            "~@clock"
            "@debug"
            "@module"
            "@mount"
            "@raw-io"
            "@reboot"
            "@swap"
            # "@privileged"
            "@resources"
            "@cpu-emulation"
            "@obsolete"
          ];
          UMask = "7007";
          InaccessiblePaths = [ "/home" "/root" ];
          LimitNOFILE = 49152;
          PermissionsStartOnly = true;
        };
      };
    };

    services.openldap = {
      enable = true;
      urlList = cfg.listen-uris;

      settings = let
        makePermEntry = dn: perm: "by ${dn} ${perm}";

        makeAccessLine = target: perm-map: let
          perm-entries = mapAttrsToList makePermEntry perm-map;
        in "to ${target} ${concatStringsSep " " perm-entries}";

        makeAccess = access-map: let
          access-lines = mapAttrsToList makeAccessLine;
          numbered-access-lines = imap0 (i: line: "{${toString i}}${line}");
        in numbered-access-lines (access-lines access-map);

      in {
        attrs = {
          cn = "config";
          objectClass = "olcGlobal";
          olcPidFile = "/run/slapd/slapd.pid";
          olcTLSCertificateFile = cfg.ssl-certificate;
          olcTLSCertificateKeyFile = cfg.ssl-private-key;
          olcTLSCACertificateFile = ca-path;
          olcSaslSecProps = "noplain,noanonymous";
          olcAuthzRegexp = let
            authz-regex-entry = i: { regex, target }:
              "{${toString i}}\"${regex}\" \"${target}\"";
          in imap0 authz-regex-entry [
            {
              regex = "^uid=auth/([^.]+).fudo.org,cn=fudo.org,cn=gssapi,cn=auth$";
              target = "cn=$1,ou=hosts,dc=fudo,dc=org";
            }
            {
              regex = "^uid=[^,/]+/root,cn=fudo.org,cn=gssapi,cn=auth$";
              target = "cn=admin,dc=fudo,dc=org";
            }
            {
              regex = "^uid=([^,/]+),cn=fudo.org,cn=gssapi,cn=auth$";
              target = "uid=$1,ou=members,dc=fudo,dc=org";
            }
            {
              regex = "^uid=host/([^,/]+),cn=fudo.org,cn=gssapi,cn=auth$";
              target = "cn=$1,ou=hosts,dc=fudo,dc=org";
            }
            {
              regex = "^gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth$";
              target = "cn=admin,dc=fudo,dc=org";
            }
          ];
        };
        children = {
          "cn=schema" = {
            includes = [
              "${pkgs.openldap}/etc/schema/core.ldif"
              "${pkgs.openldap}/etc/schema/cosine.ldif"
              "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
              "${pkgs.openldap}/etc/schema/nis.ldif"
            ];
          };
          "olcDatabase={-1}frontend" = {
            attrs = {
              objectClass = [ "olcDatabaseConfig" "olcFrontendConfig" ];
              olcDatabase = "{-1}frontend";
            };
          };
          "olcDatabase={0}config" = {
            attrs = {
              objectClass = [ "olcDatabaseConfig" ];
              olcDatabase = "{0}config";
              olcAccess = makeAccess {
                "*" = {
                  "*" = "none";
                };
              };
            };
          };
          "olcDatabase={1}mdb" = {
            attrs = {
              objectClass = [ "olcDatabaseConfig" "olcMdbConfig" ];
              olcDatabase = "{1}mdb";
              olcSuffix = cfg.base;
              # olcRootDN = "cn=admin,${cfg.base}";
              # olcRootPW = FIXME; # NOTE: this should be hashed...
              olcDbDirectory = "${cfg.state-directory}/database";
              olcDbIndex = [ "objectClass eq" "uid pres,eq" ];
              olcAccess = makeAccess {
                "attrs=userPassword,shadowLastChange" = {
                  # "dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" = "manage";
                  "dn.exact=cn=auth_reader,${cfg.base}" = "read";
                  "*" = "auth";
                };
                "dn=cn=admin,ou=groups,${cfg.base}" = {
                  # "dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" = "manage";
                  "anonymous" = "auth";
                  "dn.children=dc=fudo,dc=org" = "read";
                };
                "dn.subtree=ou=groups,${cfg.base} attrs=memberUid" = {
                  # "dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" = "manage";
                  # "dn.regex=cn=[a-zA-Z][a-zA-Z0-9_]+,ou=hosts,${cfg.base}" = "write";
                  "anonymous" = "auth";
                  "dn.children=dc=fudo,dc=org" = "read";
                };
                "dn.subtree=ou=members,${cfg.base} attrs=cn,sn,homeDirectory,loginShell,gecos,description,homeDirectory,uidNumber,gidNumber" = {
                  # "dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" = "manage";
                  "anonymous" = "auth";
                  "dn.children=dc=fudo,dc=org" = "read";
                };
                "*" = {
                  # "dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" = "manage";
                  "anonymous" = "auth";
                  "dn.children=dc=fudo,dc=org" = "read";
                };
              };
            };
          };
        };
      };

      declarativeContents = {
        "dc=fudo,dc=org" = ''
          dn: ${cfg.base}
          objectClass: top
          objectClass: dcObject
          objectClass: organization
          o: ${cfg.organization}

          dn: ou=groups,${cfg.base}
          objectClass: organizationalUnit
          description: ${cfg.organization} groups

          dn: ou=members,${cfg.base}
          objectClass: organizationalUnit
          description: ${cfg.organization} members

          dn: cn=admin,${cfg.base}
          objectClass: organizationalRole
          cn: admin
          description: "Admin User"

          ${systemUsersLdif cfg.base cfg.system-users}
          ${groupsLdif cfg.base cfg.groups}
          ${usersLdif cfg.base cfg.groups cfg.users}
        '';
      };
    };
  };
}
