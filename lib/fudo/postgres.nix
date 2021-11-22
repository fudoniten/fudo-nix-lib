{ config, lib, pkgs, environment, ... }:

with lib;
let
  cfg = config.fudo.postgresql;

  hostname = config.instance.hostname;
  domain-name = config.instance.local-domain;

  gssapi-realm = config.fudo.domains.${domain-name}.gssapi-realm;

  join-lines = lib.concatStringsSep "\n";

  strip-ext = filename:
    head (builtins.match "^(.+)[.][^.]+$" filename);

  userDatabaseOpts = { database, ... }: {
    options = {
      access = mkOption {
        type = types.str;
        description = "Privileges for user on this database.";
        default = "CONNECT";
      };

      entity-access = mkOption {
        type = with types; attrsOf str;
        description =
          "A list of entities mapped to the access this user should have.";
        default = { };
        example = {
          "TABLE users" = "SELECT,DELETE";
          "ALL SEQUENCES IN public" = "SELECT";
        };
      };
    };
  };

  userOpts = { username, ... }: {
    options = with types; {
      password-file = mkOption {
        type = nullOr str;
        description = "A file containing the user's (plaintext) password.";
        default = null;
      };

      databases = mkOption {
        type = attrsOf (submodule userDatabaseOpts);
        description = "Map of databases to required database/table perms.";
        default = { };
        example = {
          my_database = {
            access = "ALL PRIVILEGES";
            entity-access = { "ALL TABLES" = "SELECT"; };
          };
        };
      };
    };
  };

  databaseOpts = { dbname, ... }: {
    options = with types; {
      users = mkOption {
        type = listOf str;
        description =
          "A list of users who should have full access to this database.";
        default = [ ];
      };
    };
  };

  filterPasswordedUsers = filterAttrs (user: opts: opts.password-file != null);

  password-setter-script = user: password-file: sql-file: ''
    unset PASSWORD
    if [ ! -f ${password-file} ]; then
      echo "file does not exist: ${password-file}"
      exit 1
    fi
    PASSWORD=$(cat ${password-file})
    echo "setting password for user ${user}"
    echo "ALTER USER ${user} ENCRYPTED PASSWORD '$PASSWORD';" >> ${sql-file}
  '';

  passwords-setter-script = users:
    pkgs.writeScript "postgres-set-passwords.sh" ''
      if [ $# -ne 1 ]; then
        echo "usage: $0 output-file.sql"
        exit 1
      fi

      OUTPUT_FILE=$1

      if [ ! -f $OUTPUT_FILE ]; then
        echo "file doesn't exist: $OUTPUT_FILE"
        exit 2
      fi

      ${join-lines (mapAttrsToList (user: opts:
        password-setter-script user opts.password-file "$OUTPUT_FILE")
        (filterPasswordedUsers users))}
    '';

  userDatabaseAccess = user: databases:
    mapAttrs' (database: databaseOpts:
      nameValuePair "DATABASE ${database}" databaseOpts.access) databases;

  makeEntry = nw:
    "host     all             all             ${nw} gss include_realm=0 krb_realm=${gssapi-realm}";

  makeNetworksEntry = networks: join-lines (map makeEntry networks);

  makeLocalUserPasswordEntries = users:
    join-lines (mapAttrsToList (user: opts:
      join-lines (map (db: ''
        local  ${db}  ${user}   md5
        host   ${db}  ${user}   127.0.0.1/16   md5
        host   ${db}  ${user}   ::1/128        md5
      '') (attrNames opts.databases))) (filterPasswordedUsers users));

  userTableAccessSql = user: entity: access:
    "GRANT ${access} ON ${entity} TO ${user};";
  userDatabaseAccessSql = user: database: dbOpts: ''
    \c ${database}
    ${join-lines
    (mapAttrsToList (userTableAccessSql user) dbOpts.entity-access)}
  '';
  userAccessSql = user: userOpts:
    join-lines (mapAttrsToList (userDatabaseAccessSql user) userOpts.databases);
  usersAccessSql = users: join-lines (mapAttrsToList userAccessSql users);

in {

  options.fudo.postgresql = with types; {
    enable = mkEnableOption "Fudo PostgreSQL Server";

    ssl-private-key = mkOption {
      type = str;
      description = "Location of the server SSL private key.";
    };

    ssl-certificate = mkOption {
      type = str;
      description = "Location of the server SSL certificate.";
    };

    keytab = mkOption {
      type = str;
      description = "Location of the server Kerberos keytab.";
    };

    local-networks = mkOption {
      type = listOf str;
      description = "A list of networks from which to accept connections.";
      example = [ "10.0.0.1/16" ];
      default = [ ];
    };

    users = mkOption {
      type = attrsOf (submodule userOpts);
      description = "A map of users to user attributes.";
      example = {
        sampleUser = {
          password-file = "/path/to/password/file";
          databases = {
            some_database = {
              access = "CONNECT";
              entity-access = { "TABLE some_table" = "SELECT,UPDATE"; };
            };
          };
        };
      };
      default = { };
    };

    databases = mkOption {
      type = attrsOf (submodule databaseOpts);
      description = "A map of databases to database options.";
      default = { };
    };

    socket-directory = mkOption {
      type = str;
      description = "Directory in which to place unix sockets.";
      default = "/run/postgresql";
    };

    socket-group = mkOption {
      type = str;
      description = "Group for accessing sockets.";
      default = "postgres_local";
    };

    local-users = mkOption {
      type = listOf str;
      description = "Users able to access the server via local socket.";
      default = [ ];
    };

    required-services = mkOption {
      type = listOf str;
      description = "List of services that should run before postgresql.";
      default = [ ];
      example = [ "password-generator.service" ];
    };

    state-directory = mkOption {
      type = nullOr str;
      description = "Path at which to store database state data.";
      default = null;
    };

    cleanup-tasks = mkOption {
      type = listOf str;
      description = "List of actions to take during shutdown of the service.";
      default = [];
    };

    systemd-target = mkOption {
      type = str;
      description = "Name of the systemd target for postgresql";
      default = "postgresql.target";
    };
  };

  config = mkIf cfg.enable {

    environment = {
      systemPackages = with pkgs; [ postgresql_11_gssapi ];

      # etc = {
      #   "postgresql/private/privkey.pem" = {
      #     mode = "0400";
      #     user = "postgres";
      #     group = "postgres";
      #     source = cfg.ssl-private-key;
      #   };

      #   "postgresql/cert.pem" = {
      #     mode = "0444";
      #     user = "postgres";
      #     group = "postgres";
      #     source = cfg.ssl-certificate;
      #   };

      #   "postgresql/private/postgres.keytab" = {
      #     mode = "0400";
      #     user = "postgres";
      #     group = "postgres";
      #     source = cfg.keytab;
      #   };
      # };
    };

    users.groups = {
      ${cfg.socket-group} = { members = [ "postgres" ] ++ cfg.local-users; };
    };

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_11_gssapi;
      enableTCPIP = true;
      ensureDatabases = mapAttrsToList (name: value: name) cfg.databases;
      ensureUsers = ((mapAttrsToList (username: attrs: {
        name = username;
        ensurePermissions = userDatabaseAccess username attrs.databases;
      }) cfg.users) ++ (flatten (mapAttrsToList (database: opts:
        (map (username: {
          name = username;
          ensurePermissions = { "DATABASE ${database}" = "ALL PRIVILEGES"; };
        }) opts.users)) cfg.databases)));

      settings = {
        krb_server_keyfile = cfg.keytab;

        ssl = true;
        ssl_cert_file = cfg.ssl-certificate;
        ssl_key_file = cfg.ssl-private-key;

        unix_socket_directories = cfg.socket-directory;
        unix_socket_group = cfg.socket-group;
        unix_socket_permissions = "0777";
      };

      authentication = lib.mkForce ''
        ${makeLocalUserPasswordEntries cfg.users}

        local   all              all             ident

        # host-local
        host    all              all             127.0.0.1/32            gss include_realm=0 krb_realm=${gssapi-realm}
        host    all              all             ::1/128                 gss include_realm=0 krb_realm=${gssapi-realm}

        # local networks
        ${makeNetworksEntry cfg.local-networks}
      '';

      dataDir = mkIf (cfg.state-directory != null) cfg.state-directory;
    };

    systemd = {

      tmpfiles.rules = optional (cfg.state-directory != null) (let
        user = config.systemd.services.postgresql.serviceConfig.User;
      in "d ${cfg.state-directory} 0700 ${user} - - -");

      targets.${strip-ext cfg.systemd-target} = {
        description = "Postgresql and associated systemd services.";
      };

      services = {
        postgresql-password-setter = let
          passwords-script = passwords-setter-script cfg.users;
          password-wrapper-script =
            pkgs.writeScript "password-script-wrapper.sh" ''
              TMPDIR=$(${pkgs.coreutils}/bin/mktemp -d -t postgres-XXXXXXXXXX)
              echo "using temp dir $TMPDIR"
              PASSWORD_SQL_FILE=$TMPDIR/user-passwords.sql
              echo "password file $PASSWORD_SQL_FILE"
              touch $PASSWORD_SQL_FILE
              chown ${config.services.postgresql.superUser} $PASSWORD_SQL_FILE
              chmod go-rwx $PASSWORD_SQL_FILE
              ${passwords-script} $PASSWORD_SQL_FILE
              echo "executing $PASSWORD_SQL_FILE"
              ${pkgs.postgresql}/bin/psql --port ${
                toString config.services.postgresql.port
              } -d postgres -f $PASSWORD_SQL_FILE
              echo rm $PASSWORD_SQL_FILE
              echo "Postgresql user passwords set.";
              exit 0
            '';

        in {
          description =
            "A service to set postgresql user passwords after the server has started.";
          after = [ "postgresql.service" ] ++ cfg.required-services;
          requires = [ "postgresql.service" ] ++ cfg.required-services;
          serviceConfig = {
            Type = "oneshot";
            User = config.services.postgresql.superUser;
          };
          partOf = [ cfg.systemd-target ];
          script = "${password-wrapper-script}";
        };

        postgresql = {
          requires = cfg.required-services;
          after = cfg.required-services;
          partOf = [ cfg.systemd-target ];

          postStart = let
            allow-user-login = user: "ALTER ROLE ${user} WITH LOGIN;";

            extra-settings-sql = pkgs.writeText "settings.sql" ''
            ${concatStringsSep "\n"
              (map allow-user-login (mapAttrsToList (key: val: key) cfg.users))}
            ${usersAccessSql cfg.users}
          '';
            in ''
            ${pkgs.postgresql}/bin/psql --port ${
              toString config.services.postgresql.port
            } -d postgres -f ${extra-settings-sql}
            ${pkgs.coreutils}/bin/chgrp ${cfg.socket-group} ${cfg.socket-directory}/.s.PGSQL*
          '';

          postStop = concatStringsSep "\n" cfg.cleanup-tasks;
        };
      };
    };
  };
}
