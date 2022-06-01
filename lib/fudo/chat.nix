{ pkgs, lib, config, ... }:

with lib;
let
  cfg = config.fudo.chat;
  mattermost-config-target = "/run/chat/mattermost/mattermost-config.json";

in {
  options.fudo.chat = with types; {
    enable = mkEnableOption "Enable chat server";

    hostname = mkOption {
      type = str;
      description = "Hostname at which this chat server is accessible.";
      example = "chat.mydomain.com";
    };

    site-name = mkOption {
      type = str;
      description = "The name of this chat server.";
      example = "My Fancy Chat Site";
    };

    user = mkOption {
      type = str;
      description = "System user as which to run the server.";
      default = "mattermost";
    };

    group = mkOption {
      type = str;
      description = "System group as which to run the server.";
      default = "mattermost";
    };

    smtp = {
      server = mkOption {
        type = str;
        description = "SMTP server to use for sending notification emails.";
        example = "mail.my-site.com";
      };

      user = mkOption {
        type = str;
        description = "Username with which to connect to the SMTP server.";
      };

      password-file = mkOption {
        type = str;
        description =
          "Path to a file containing the password to use while connecting to the SMTP server.";
      };
    };

    state-directory = mkOption {
      type = str;
      description = "Path at which to store server state data.";
      default = "/var/lib/mattermost";
    };

    database = mkOption {
      type = (submodule {
        options = {
          name = mkOption {
            type = str;
            description = "Database name.";
          };

          hostname = mkOption {
            type = str;
            description = "Database host.";
          };

          user = mkOption {
            type = str;
            description = "Database user.";
          };

          password-file = mkOption {
            type = str;
            description = "Path to file containing database password.";
          };
        };
      });
      description = "Database configuration.";
      example = {
        name = "my_database";
        hostname = "my.database.com";
        user = "db_user";
        password-file = /path/to/some/file.pw;
      };
    };
  };

  config = mkIf cfg.enable (let
    pkg = pkgs.mattermost;
    default-config = builtins.fromJSON (readFile "${pkg}/config/config.json");
    modified-config = recursiveUpdate default-config {
      ServiceSettings.SiteURL = "https://${cfg.hostname}";
      ServiceSettings.ListenAddress = "127.0.0.1:8065";
      TeamSettings.SiteName = cfg.site-name;
      EmailSettings = {
        RequireEmailVerification = true;
        SMTPServer = cfg.smtp.server;
        SMTPPort = "587";
        EnableSMTPAuth = true;
        SMTPUsername = cfg.smtp.user;
        SMTPPassword = "__SMTP_PASSWD__";
        SendEmailNotifications = true;
        ConnectionSecurity = "STARTTLS";
        FeedbackEmail = "chat@fudo.org";
        FeedbackName = "Admin";
      };
      EnableEmailInvitations = true;
      SqlSettings.DriverName = "postgres";
      SqlSettings.DataSource =
        "postgres://${cfg.database.user}:__DATABASE_PASSWORD__@${cfg.database.hostname}:5432/${cfg.database.name}";
    };
    mattermost-config-file-template =
      pkgs.writeText "mattermost-config.json.template"
      (builtins.toJSON modified-config);

    generate-mattermost-config =
      target: template: smtp-passwd-file: db-passwd-file:
      pkgs.writeScript "mattermost-config-generator.sh" ''
        rm ${target}
        SMTP_PASSWD=$( cat ${smtp-passwd-file} )
        DATABASE_PASSWORD=$( cat ${db-passwd-file} )
        sed -e "s/__SMTP_PASSWD__/$SMTP_PASSWD/" -e "s/__DATABASE_PASSWORD__/$DATABASE_PASSWORD/" ${template} > ${target}
      '';

  in {
    users = {
      users = {
        ${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
        };
      };
      groups = { ${cfg.group} = { members = [ cfg.user ]; }; };
    };

    fudo.system.services.mattermost = {
      description = "Mattermost Chat Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      preStart =
        let config-target = "${cfg.state-directory}/config/config.json";
        in ''
          if [ ! -f ${config-target} ]; then
            ${
              generate-mattermost-config mattermost-config-target
              mattermost-config-file-template cfg.smtp.password-file
              cfg.database.password-file
            }
            cp ${mattermost-config-target} ${config-target}
            chown ${cfg.user}:${cfg.group} ${config-target}
            chmod 640 ${config-target}
          fi
          if [ ! -e ${cfg.state-directory} ]; then
            cp -uRL ${pkg}/client ${cfg.state-directory}
            chown ${cfg.user}:${cfg.group} ${cfg.state-directory}/client
            chmod 0750 ${cfg.state-directory}/client
          fi
        '';
      execStart = "${pkg}/bin/mattermost";
      workingDirectory = cfg.state-directory;
      user = cfg.user;
      group = cfg.group;
    };

    systemd = {

      tmpfiles.rules = [
        "d ${cfg.state-directory} 0750 ${cfg.user} - - -"
        "d ${cfg.state-directory}/config 0750 ${cfg.user} - - -"
        "d ${dirOf mattermost-config-target} 0750 ${cfg.user} - - -"
        "L ${cfg.state-directory}/bin - - - - ${pkg}/bin"
        "L ${cfg.state-directory}/fonts - - - - ${pkg}/fonts"
        "L ${cfg.state-directory}/i18n - - - - ${pkg}/i18n"
        "L ${cfg.state-directory}/templates - - - - ${pkg}/templates"
      ];
    };

    services.nginx = {
      enable = true;

      appendHttpConfig = ''
        proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=mattermost_cache:10m max_size=3g inactive=120m use_temp_path=off;
      '';

      recommendedProxySettings = true;

      virtualHosts = {
        "${cfg.hostname}" = {
          enableACME = true;
          forceSSL = true;

          locations."/" = {
            proxyPass = "http://127.0.0.1:8065";
            proxyWebsockets = true;

            # extraConfig = ''
            #   client_max_body_size 50M;
            #   proxy_set_header Connection "";
            #   proxy_set_header Host $host;
            #   proxy_set_header X-Real-IP $remote_addr;
            #   proxy_set_header X-Forwarded-By $server_addr:$server_port;
            #   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            #   proxy_set_header X-Forwarded-Proto $scheme;
            #   proxy_set_header X-Frame-Options SAMEORIGIN;
            #   proxy_buffers 256 16k;
            #   proxy_buffer_size 16k;
            #   proxy_read_timeout 600s;
            #   proxy_cache mattermost_cache;
            #   proxy_cache_revalidate on;
            #   proxy_cache_min_uses 2;
            #   proxy_cache_use_stale timeout;
            #   proxy_cache_lock on;
            #   proxy_http_version 1.1;
            # '';
          };

          # locations."~ /api/v[0-9]+/(users/)?websocket$" = {
          #   proxyPass = "http://127.0.0.1:8065";

          #   extraConfig = ''
          #     proxy_set_header Upgrade $http_upgrade;
          #     proxy_set_header Connection "upgrade";
          #     client_max_body_size 50M;
          #     proxy_set_header Host $host;
          #     proxy_set_header X-Real-IP $remote_addr;
          #     proxy_set_header X-Forwarded-By $server_addr:$server_port;
          #     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          #     proxy_set_header X-Forwarded-Proto $scheme;
          #     proxy_set_header X-Frame-Options SAMEORIGIN;
          #     proxy_buffers 256 16k;
          #     proxy_buffer_size 16k;
          #     client_body_timeout 60;
          #     send_timeout 300;
          #     lingering_timeout 5;
          #     proxy_connect_timeout 90;
          #     proxy_send_timeout 300;
          #     proxy_read_timeout 90s;
          #   '';
          # };
        };
      };
    };
  });
}
