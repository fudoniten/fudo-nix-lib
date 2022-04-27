{ pkgs, lib, config, ... }:

with lib;
let
  cfg = config.fudo.git;

  databaseOpts = { ... }: {
    options = {
      name = mkOption {
        type = types.str;
        description = "Database name.";
      };
      hostname = mkOption {
        type = types.str;
        description = "Hostname of the database server.";
      };
      user = mkOption {
        type = types.str;
        description = "Database username.";
      };
      password-file = mkOption {
        type = types.path;
        description = "File containing the database user's password.";
      };
    };
  };

  sshOpts = { ... }:
    with types; {
      options = {
        listen-ip = mkOption {
          type = str;
          description = "IP on which to listen for SSH connections.";
        };

        listen-port = mkOption {
          type = port;
          description =
            "Port on which to listen for SSH connections, on <listen-ip>.";
          default = 22;
        };
      };
    };

in {
  options.fudo.git = with types; {
    enable = mkEnableOption "Enable Fudo git web server.";

    hostname = mkOption {
      type = str;
      description = "Hostname at which this git server is accessible.";
      example = "git.fudo.org";
    };

    site-name = mkOption {
      type = str;
      description = "Name to use for the git server.";
      default = "Fudo Git";
    };

    database = mkOption {
      type = (submodule databaseOpts);
      description = "Gitea database options.";
    };

    repository-dir = mkOption {
      type = str;
      description = "Path at which to store repositories.";
      example = "/srv/git/repo";
    };

    state-dir = mkOption {
      type = str;
      description = "Path at which to store server state.";
      example = "/srv/git/state";
    };

    user = mkOption {
      type = with types; nullOr str;
      description = "System user as which to run.";
      default = "git";
    };

    local-port = mkOption {
      type = port;
      description =
        "Local port to which the Gitea server will bind. Not globally accessible.";
      default = 3543;
    };

    ssh = mkOption {
      type = nullOr (submodule sshOpts);
      description = "SSH listen configuration.";
      default = null;
    };
  };

  config = mkIf cfg.enable {
    security.acme.certs.${cfg.hostname}.email =
      let domain-name = config.fudo.hosts.${config.instance.hostname}.domain;
      in config.fudo.domains.${domain-name}.admin-email;

    networking.firewall.allowedTCPPorts =
      mkIf (cfg.ssh != null) [ cfg.ssh.listen-port ];

    environment.systemPackages = with pkgs;
      let
        gitea-admin = writeShellScriptBin "gitea-admin" ''
          TMP=$(mktemp -d /tmp/gitea-XXXXXXXX)
          ${gitea}/bin/gitea --custom-path ${cfg.state-dir}/custom --config ${cfg.state-dir}/custom/conf/app.ini --work-path $TMP $@
        '';
      in [ gitea-admin ];

    services = {
      gitea = {
        enable = true;
        appName = cfg.site-name;
        database = {
          createDatabase = false;
          host = cfg.database.hostname;
          name = cfg.database.name;
          user = cfg.database.user;
          passwordFile = cfg.database.password-file;
          type = "postgres";
        };
        domain = cfg.hostname;
        httpAddress = "127.0.0.1";
        httpPort = cfg.local-port;
        repositoryRoot = cfg.repository-dir;
        stateDir = cfg.state-dir;
        rootUrl = "https://${cfg.hostname}/";
        user = mkIf (cfg.user != null) cfg.user;
        ssh = {
          enable = true;
          clonePort = cfg.ssh.listen-port;
        };
        settings = mkIf (cfg.ssh != null) {
          server = {
            # Displayed in the clone URL
            SSH_DOMAIN = cfg.hostname;
            SSH_PORT = mkForce cfg.ssh.listen-port;

            # Actual ip/port on which to listen
            SSH_LISTEN_PORT = cfg.ssh.listen-port;
            SSH_LISTEN_HOST = cfg.ssh.listen-ip;
          };
        };
      };

      nginx = {
        enable = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;

        virtualHosts = {
          "${cfg.hostname}" = {
            enableACME = true;
            forceSSL = true;

            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString cfg.local-port}";
            };
          };
        };
      };
    };
  };
}
