{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;
  
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
    cert-copy.chain
  ];

  siteCertService = site:
    host-domains.${site}.local-copies.ejabberd.service;

  config-file-template = let
    jabber-config = {
      loglevel = cfg.log-level;

      access_rules = {
        c2s = { allow = "all"; };
        announce = { allow = "admin"; };
        configure = { allow = "admin"; };
        pubsub_createnode = { allow = "local"; };
      };

      acl = {
        admin = {
          user = concatMap
            (admin: map (site: "${admin}@${site}")
              (attrNames cfg.sites))
            cfg.admins;
        };
      };

      hosts = attrNames cfg.sites;

      listen = map (ip: {
        port = cfg.port;
        module = "ejabberd_c2s";
        ip = ip;
        starttls = true;
        starttls_required = true;
      }) cfg.listen-ips;

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
    secret-readers = concatStringsSep "\n"
      (mapAttrsToList
        (secret: file: "${secret}=$(cat ${file})")
        secrets);
    secret-swappers = map
      (secret: "sed s/${secret}/\$${secret}/g")
      (attrNames secrets);
    swapper = concatStringsSep " | " secret-swappers;
  in pkgs.writeShellScript "ejabberd-generate-config.sh" ''
    cat ${template} | ${swapper} > ${target}
  '';

  cfg = config.fudo.jabber;
  
in {
  options.fudo.jabber = with types; {
    enable = mkEnableOption "Enable ejabberd server.";

    listen-ips = mkOption {
      type = listOf str;
      description = "IPs on which to listen for Jabber connections.";
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
      default = "/run/ejabberd/ejabberd.yaml";
    };

    log-level = mkOption {
      type = int;
      description = ''
        Log level at which to run the server.

        See: https://docs.ejabberd.im/admin/guide/troubleshooting/
      '';
      default = 3;
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

    fudo = {
      acme.host-domains.${hostname} = mapAttrs (site: siteCfg:
        mkIf siteCfg.enableACME {
          local-copies.ejabberd = {
            user = cfg.user;
            group = cfg.group;
          };
        }) cfg.sites;

      system = {
        services.ejabberd-config-generator = let
          config-generator =
            enter-secrets config-file-template cfg.secret-files cfg.config-file;
        in {
          script = "${config-generator}";
          readWritePaths = [ config-dir ];
          workingDirectory = config-dir;
          user = cfg.user;
          description = "Generate ejabberd config file with necessary passwords.";
          postStart = ''
            chown ${cfg.user} ${cfg.config-file}
            chmod 0400 ${cfg.config-file}
          '';
        };
      };
    };

    systemd = {
      tmpfiles.rules = [
        "d '${config-dir}' 0700 ${cfg.user} ${cfg.group} - -'"
      ];
      
      services = {
        ejabberd = {
          wants = map (site: siteCertService site) (attrNames cfg.sites);
          requires = [ "ejabberd-config-generator.service" ];
          environment = cfg.environment;
        };
      };
    };
    
    services.ejabberd = {
      enable = true;

      user = cfg.user;
      group = cfg.group;

      configFile = cfg.config-file;
    };
  };
}
