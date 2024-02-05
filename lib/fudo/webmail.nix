{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;

  cfg = config.fudo.webmail;

  base-data-path = cfg.state-directory;

  webmail-user = cfg.user;
  webmail-group = cfg.group;

  concatMapAttrs = f: attrs: foldr (a: b: a // b) { } (mapAttrsToList f attrs);

  fastcgi-conf = builtins.toFile "fastcgi.conf" ''
    fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
    fastcgi_param  QUERY_STRING       $query_string;
    fastcgi_param  REQUEST_METHOD     $request_method;
    fastcgi_param  CONTENT_TYPE       $content_type;
    fastcgi_param  CONTENT_LENGTH     $content_length;

    fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
    fastcgi_param  REQUEST_URI        $request_uri;
    fastcgi_param  DOCUMENT_URI       $document_uri;
    fastcgi_param  DOCUMENT_ROOT      $document_root;
    fastcgi_param  SERVER_PROTOCOL    $server_protocol;
    fastcgi_param  REQUEST_SCHEME     $scheme;
    fastcgi_param  HTTPS              $https if_not_empty;

    fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
    fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

    fastcgi_param  REMOTE_ADDR        $remote_addr;
    fastcgi_param  REMOTE_PORT        $remote_port;
    fastcgi_param  SERVER_ADDR        $server_addr;
    fastcgi_param  SERVER_PORT        $server_port;
    fastcgi_param  SERVER_NAME        $server_name;

    # PHP only, required if PHP was built with --enable-force-cgi-redirect
    fastcgi_param  REDIRECT_STATUS    200;
  '';

  site-packages = mapAttrs (site: site-cfg:
    pkgs.rainloop-community.overrideAttrs (oldAttrs: {
      # Not sure how to correctly specify this arg...
      #dataPath = "${base-data-path}/${site}";

      # Overwriting, to correctly create data dir
      installPhase = ''
        mkdir $out
        cp -r rainloop/* $out
        rm -rf $out/data
        ln -s ${base-data-path}/${site} $out/data
        ln -s ${site-cfg.favicon} $out/favicon.ico
      '';
    })) cfg.sites;

  siteOpts = { name, ... }:
    with types; {
      options = {
        title = mkOption {
          type = str;
          description = "Webmail site title";
          example = "My Webmail";
        };

        debug = mkOption {
          type = bool;
          description = "Turn debug logs on.";
          default = false;
        };

        mail-server = mkOption {
          type = str;
          description = "Mail server from which to send & recieve email.";
          default = "mail.fudo.org";
        };

        favicon = mkOption {
          type = str;
          description = "URL of the site favicon";
          example = "https://www.somepage.com/fav.ico";
        };

        messages-per-page = mkOption {
          type = int;
          description = "Default number of messages to show per page";
          default = 30;
        };

        max-upload-size = mkOption {
          type = int;
          description = "Size limit in MB for uploaded files";
          default = 30;
        };

        theme = mkOption {
          type = str;
          description = "Default theme to use for this webmail site.";
          default = "Default";
        };

        domain = mkOption {
          type = str;
          description = "Domain for which the server acts as webmail server";
        };

        edit-mode = mkOption {
          type = enum [ "Plain" "Html" "PlainForced" "HtmlForced" ];
          description = "Default text editing mode for email";
          default = "Html";
        };

        layout-mode = mkOption {
          type = enum [ "side" "bottom" ];
          description = "Layout mode to use for email preview.";
          default = "side";
        };

        enable-threading = mkOption {
          type = bool;
          description = "Whether to enable threading for email.";
          default = true;
        };

        enable-mobile = mkOption {
          type = bool;
          description = "Whether to enable a mobile site view.";
          default = true;
        };

        database = mkOption {
          type = nullOr (submodule databaseOpts);
          description = "Database configuration for storing contact data.";
          example = {
            name = "my_db";
            host = "db.domain.com";
            user = "my_user";
            password-file = /path/to/some/file.pw;
          };
          default = null;
        };

        admin-email = mkOption {
          type = str;
          description = "Email of administrator of this site.";
          default = "admin@fudo.org";
        };
      };
    };

  databaseOpts = { ... }:
    with types; {
      options = {
        type = mkOption {
          type = enum [ "pgsql" "mysql" ];
          description = "Driver to use when connecting to the database.";
          default = "pgsql";
        };

        hostname = mkOption {
          type = str;
          description = "Name of host running the database.";
          example = "my-db.domain.com";
        };

        port = mkOption {
          type = int;
          description = "Port on which the database server is listening.";
          default = 5432;
        };

        name = mkOption {
          type = str;
          description =
            "Name of the database containing contact info. <user> must have access.";
          default = "rainloop_webmail";
        };

        user = mkOption {
          type = str;
          description = "User as which to connect to the database.";
          default = "webmail";
        };

        password-file = mkOption {
          type = nullOr str;
          description = ''
            Password to use when connecting to the database.

            If unset, a random password will be generated.
          '';
        };
      };
    };

in {
  options.fudo.webmail = with types; {
    enable = mkEnableOption "Enable a RainLoop webmail server.";

    sites = mkOption {
      type = attrsOf (submodule siteOpts);
      description = "A map of webmail sites to site configurations.";
      example = {
        "webmail.domain.com" = {
          title = "My Awesome Webmail";
          layout-mode = "side";
          favicon = "/path/to/favicon.ico";
          admin-password = "shh-don't-tell";
        };
      };
    };

    state-directory = mkOption {
      type = str;
      description = "The path at which to store server state.";
    };

    user = mkOption {
      type = str;
      description = "User as which webmail will run.";
      default = "webmail-php";
    };

    group = mkOption {
      type = str;
      description = "Group as which webmail will run.";
      default = "webmail-php";
    };
  };

  config = mkIf cfg.enable {
    users = {
      users = {
        ${webmail-user} = {
          isSystemUser = true;
          description = "Webmail PHP FPM user";
          group = webmail-group;
        };
      };
      groups = {
        ${webmail-group} = {
          members = [ webmail-user config.services.nginx.user ];
        };
      };
    };

    security.acme.certs =
      mapAttrs (site: site-cfg: { email = site-cfg.admin-email; }) cfg.sites;

    services = {
      phpfpm = {
        pools.webmail = {
          settings = {
            "pm" = "dynamic";
            "pm.max_children" = 50;
            "pm.start_servers" = 5;
            "pm.min_spare_servers" = 1;
            "pm.max_spare_servers" = 8;
          };

          phpOptions = ''
            memory_limit = 500M
          '';

          # Not working....see chmod below
          user = webmail-user;
          group = webmail-group;
        };
      };

      nginx = {
        enable = true;

        virtualHosts = mapAttrs (site: site-cfg: {
          enableACME = true;
          forceSSL = true;

          root = "${site-packages.${site}}";

          locations = {
            "/" = { index = "index.php"; };

            "/data" = {
              extraConfig = ''
                deny all;
                return 403;
              '';
            };
          };

          extraConfig = ''
            location ~ \.php$ {
              expires -1;

              include ${fastcgi-conf};
              fastcgi_index index.php;
              fastcgi_pass unix:${config.services.phpfpm.pools.webmail.socket};
            }
          '';
        }) cfg.sites;
      };
    };

    fudo.secrets.host-secrets.${hostname} = concatMapAttrs (site: site-cfg:
      let

        site-config-file = builtins.toFile "${site}-rainloop.cfg"
          (import ./include/rainloop.nix lib site site-cfg
            site-packages.${site}.version);

        domain-config-file = builtins.toFile "${site}-domain.cfg" ''
          imap_host = "${site-cfg.mail-server}"
          imap_port = 143
          imap_secure = "TLS"
          imap_short_login = On
          sieve_use = Off
          sieve_allow_raw = Off
          sieve_host = ""
          sieve_port = 4190
          sieve_secure = "None"
          smtp_host = "${site-cfg.mail-server}"
          smtp_port = 587
          smtp_secure = "TLS"
          smtp_short_login = On
          smtp_auth = On
          smtp_php_mail = Off
          white_list = ""
        '';
      in {
        "${site}-site-config" = {
          source-file = site-config-file;
          target-file = "/var/run/webmail/rainloop/site-${site}-rainloop.cfg";
          user = cfg.user;
        };

        "${site}-domain-config" = {
          source-file = domain-config-file;
          target-file = "/var/run/webmail/rainloop/domain-${site}-rainloop.cfg";
          user = cfg.user;
        };
      }) cfg.sites;

    # TODO: make this a fudo service
    systemd.services = {
      webmail-init = let
        link-configs = concatStringsSep "\n" (mapAttrsToList (site: site-cfg:
          let
            cfg-file =
              config.fudo.secrets.host-secrets.${hostname}."${site}-site-config".target-file;
            domain-cfg-file =
              config.fudo.secrets.host-secrets.${hostname}."${site}-domain-config".target-file;
          in ''
            ${pkgs.coreutils}/bin/mkdir -p ${base-data-path}/${site}/_data_/_default_/configs
            ${pkgs.coreutils}/bin/cp ${cfg-file} ${base-data-path}/${site}/_data_/_default_/configs/application.ini

            ${pkgs.coreutils}/bin/mkdir -p ${base-data-path}/${site}/_data_/_default_/domains/
            ${pkgs.coreutils}/bin/cp ${domain-cfg-file} ${base-data-path}/${site}/_data_/_default_/domains/${site-cfg.domain}.ini
          '') cfg.sites);
        scriptPkg = (pkgs.writeScriptBin "webmail-init.sh" ''
          #!${pkgs.bash}/bin/bash -e
          ${link-configs}
          ${pkgs.coreutils}/bin/chown -R ${webmail-user}:${webmail-group} ${base-data-path}
          ${pkgs.coreutils}/bin/chmod -R u+w ${base-data-path}
        '');
      in {
        requiredBy = [ "nginx.service" ];
        description =
          "Initialize webmail service directories prior to starting nginx.";
        script = "${scriptPkg}/bin/webmail-init.sh";
      };

      phpfpm-webmail-socket-perm = {
        wantedBy = [ "multi-user.target" ];
        description =
          "Change ownership of the phpfpm socket for webmail once it's started.";
        requires = [ "phpfpm-webmail.service" ];
        after = [ "phpfpm.target" ];
        serviceConfig = {
          ExecStart = ''
            ${pkgs.coreutils}/bin/chown ${webmail-user}:${webmail-group} ${config.services.phpfpm.pools.webmail.socket}
          '';
        };
      };

      nginx = {
        requires =
          [ "webmail-init.service" "phpfpm-webmail-socket-perm.service" ];
      };
    };
  };
}
