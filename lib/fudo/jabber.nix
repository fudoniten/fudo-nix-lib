{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;

  host-secrets = config.fudo.secrets.host-secrets.${hostname};
  
  siteOpts = { ... }: with types; {
    options = {
      enableACME = mkOption {
        type = bool;
        description = "Use ACME to get SSL certificates for this site.";
        default = true;
      };
        
      site-config = mkOption {
        type = attrs;
        description = "Site-specific configuration.";
      };
    };
  };

  config-dir = dirOf cfg.config-file;

  concatMapAttrs = f: attrs:
    foldr (a: b: a // b) {} (mapAttrs f attrs);

  concatMapAttrsToList = f: attr:
    concatMap (i: i) (attrValues (mapAttrs f attr));

  host-domains = config.fudo.acme.host-domains.${hostname};

  siteCerts = site: let
    cert-copy = host-domains.${site}.local-copies.ejabberd;
  in [
    cert-copy.certificate
    cert-copy.private-key
    # cert-copy.full-certificate
  ];

  siteCertService = site:
    host-domains.${site}.local-copies.ejabberd.service;

  config-file-template = let
    jabber-config = {
      loglevel = cfg.log-level;

      access_rules = {
        c2s.allow = "all";
        announce.allow = "admin";
        configure.allow = "admin";
        pubsub_createnode.allow = "admin";
      };

      acl.admin = {
        user = concatMap
          (admin: map (site: "${admin}@${site}")
            (attrNames cfg.sites))
          cfg.admins;
      };

      hosts = attrNames cfg.sites;

      # By default, listen on all ips
      listen = let
        common = {
          port = cfg.port;
          module = "ejabberd_c2s";
          starttls = true;
          starttls_required = true;
        };
      in
        if (cfg.listen-ips != null) then
          map (ip: { ip = ip; } // common)
            cfg.listen-ips
        else [ common ];

      certfiles = concatMapAttrsToList
        (site: siteOpts:
          if (siteOpts.enableACME) then
            (siteCerts site)
          else [])
        cfg.sites;

      host_config =
        mapAttrs (site: siteOpts: siteOpts.site-config)
          cfg.sites;
    };
    
    config-file = builtins.toJSON jabber-config;
  in pkgs.writeText "ejabberd.config.yml.template" config-file;

  enter-secrets = template: secrets: target: let
    secret-swappers = map
      (secret: "sed s/${secret}/\$${secret}/g")
      secrets;
    swapper = concatStringsSep " | " secret-swappers;
  in pkgs.writeShellScript "ejabberd-generate-config.sh" ''
    [ -f \$${target} ] && rm -f ${target}
    echo "Copying from ${template} to ${target}"
    touch ${target}
    chmod go-rwx ${target}
    chmod u+rw ${target}
    cat ${template} | ${swapper} > ${target}
    echo "Copying from ${template} to ${target} completed"
  '';

  cfg = config.fudo.jabber;

  log-dir = "${cfg.state-directory}/logs";
  spool-dir = "${cfg.state-directory}/spool";
  
in {
  options.fudo.jabber = with types; {
    enable = mkEnableOption "Enable ejabberd server.";

    listen-ips = mkOption {
      type = nullOr (listOf str);
      description = "IPs on which to listen for Jabber connections.";
      default = null;
    };
    
    port = mkOption {
      type = port;
      description = "Port on which to listen for Jabber connections.";
      default = 5222;
    };

    user = mkOption {
      type = str;
      description = "User as which to run the ejabberd server.";
      default = "ejabberd";
    };

    group = mkOption {
      type = str;
      description = "Group as which to run the ejabberd server.";
      default = "ejabberd";
    };

    admins = mkOption {
      type = listOf str;
      description = "List of admin users for the server.";
      default = [];
    };

    sites = mkOption {
      type = attrsOf (submodule siteOpts);
      description = "List of sites on which to listen for Jabber connections.";
    };

    secret-files = mkOption {
      type = attrsOf str;
      description = "Map of secret-name to file. File contents will be subbed for the name in the config.";
      default = {};
    };

    config-file = mkOption {
      type = str;
      description = "Location at which to generate the configuration file.";
      default = "/run/ejabberd/config/ejabberd.yaml";
    };

    log-level = mkOption {
      type = int;
      description = ''
        Log level at which to run the server.

        See: https://docs.ejabberd.im/admin/guide/troubleshooting/
      '';
      default = 3;
    };

    state-directory = mkOption {
      type = str;
      description = "Path at which to store ejabberd state.";
      default = "/var/lib/ejabberd";
    };

    environment = mkOption {
      type = attrsOf str;
      description = "Environment variables to set for the ejabberd daemon.";
      default = {};
    };
  };
  
  config = mkIf cfg.enable {
    users = {
      users.${cfg.user} = {
        isSystemUser = true;
      };

      groups.${cfg.group} = {
        members = [ cfg.user ];
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ 5222 5223 5269 8010 ];
    };

    fudo = let
      host-fqdn = config.instance.host-fqdn;
    in {
      acme.host-domains.${hostname} = mapAttrs (site: siteCfg:
        mkIf siteCfg.enableACME {
          extra-domains = optional (site != host-fqdn) host-fqdn;
          local-copies.ejabberd = {
            user = cfg.user;
            group = cfg.group;
          };
        }) cfg.sites;

      secrets.host-secrets.${hostname}.ejabberd-password-env = let
        env-vars = mapAttrsToList (secret: file: "${secret}=${readFile file}")
          cfg.secret-files;
      in {
        source-file = pkgs.writeText "ejabberd-password-env"
          (concatStringsSep "\n" env-vars);
        target-file = "/run/ejabberd/environment/config-passwords.env";
        user = cfg.user;
      };

      # system = {
      #   services.ejabberd-config-generator = let
      #     config-generator =
      #       enter-secrets config-file-template cfg.secret-files cfg.config-file;
      #   in {
      #     script = "${config-generator}";
      #     readWritePaths = [ config-dir ];
      #     workingDirectory = config-dir;
      #     user = cfg.user;
      #     description = "Generate ejabberd config file with necessary passwords.";
      #     postStart = ''
      #       chown ${cfg.user}:${cfg.group} ${cfg.config-file}
      #       chmod 0400 ${cfg.config-file}
      #     '';
      #   };
      # };
    };

    systemd = {
      tmpfiles.rules = [
        "d ${config-dir} 0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.state-directory} 0750 ${cfg.user} ${cfg.group} - -"
      ];
      
      services = {
        ejabberd = {
          wants = map (site: siteCertService site) (attrNames cfg.sites);
          requires = [ "ejabberd-config-generator.service" ];
          environment = cfg.environment;
        };

        ejabberd-config-generator = let
          config-generator =
            enter-secrets config-file-template (attrNames cfg.secret-files) cfg.config-file;
        in {
          description = "Generate ejabberd config file containing passwords.";
          serviceConfig = {
            User = cfg.user;
            ExecStart = "${config-generator}";
            ExecStartPost = pkgs.writeShellScript "protect-ejabberd-config.sh" ''
              chown ${cfg.user}:${cfg.group} ${cfg.config-file}
              chmod 0400 ${cfg.config-file}
            '';
            EnvironmentFile = host-secrets.ejabberd-password-env.target-file;
          };
          requires = [ host-secrets.ejabberd-password-env.service ];
        };
      };
    };
    
    services.ejabberd = {
      enable = true;

      user = cfg.user;
      group = cfg.group;

      configFile = cfg.config-file;

      logsDir = log-dir;
      spoolDir = spool-dir;
    };
  };
}
