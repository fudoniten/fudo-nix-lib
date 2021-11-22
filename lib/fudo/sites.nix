{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;
  site-name = config.fudo.hosts.${hostname}.site;
  site-cfg = config.fudo.sites.${site-name};

  site-hosts = filterAttrs (hostname: hostOpts: hostOpts.site == site-name)
    config.fudo.hosts;

  siteOpts = { site, ... }: {
    options = with types; {
      site = mkOption {
        type = str;
        description = "Site name.";
        default = site;
      };

      network = mkOption {
        type = str;
        description = "Network to be treated as local.";
      };

      dynamic-network = mkOption {
        type = nullOr str;
        description = "Network to be allocated by DHCP.";
        default = null;
      };

      gateway-v4 = mkOption {
        type = nullOr str;
        description = "Gateway to use for public ipv4 internet access.";
        default = null;
      };

      gateway-v6 = mkOption {
        type = nullOr str;
        description = "Gateway to use for public ipv6 internet access.";
        default = null;
      };

      local-groups = mkOption {
        type = listOf str;
        description = "List of groups which should exist at this site.";
        default = [ ];
      };

      local-users = mkOption {
        type = listOf str;
        description =
          "List of users which should exist on all hosts at this site.";
        default = [ ];
      };

      local-admins = mkOption {
        type = listOf str;
        description =
          "List of admin users which should exist on all hosts at this site.";
        default = [ ];
      };

      enable-monitoring =
        mkEnableOption "Enable site-wide monitoring with prometheus.";

      nameservers = mkOption {
        type = listOf str;
        description = "List of nameservers to be used by hosts at this site.";
        default = [ ];
      };

      timezone = mkOption {
        type = str;
        description = "Timezone of the site.";
        example = "America/Winnipeg";
      };

      deploy-pubkeys = mkOption {
        type = nullOr (listOf str);
        description = "SSH pubkey of site deploy key. Used by dropbear daemon.";
        default = null;
      };

      enable-ssh-backdoor = mkOption {
        type = bool;
        description =
          "Enable a backup SSH server in case of failures of the primary.";
        default = true;
      };

      dropbear-rsa-key-path = mkOption {
        type = str;
        description = "Location of Dropbear RSA key.";
        default = "/etc/dropbear/host_rsa_key";
      };

      dropbear-ecdsa-key-path = mkOption {
        type = str;
        description = "Location of Dropbear ECDSA key.";
        default = "/etc/dropbear/host_ecdsa_key";
      };

      dropbear-ssh-port = mkOption {
        type = port;
        description = "Port to be used for the backup SSH server.";
        default = 2112;
      };

      enable-distributed-builds =
        mkEnableOption "Enable distributed builds for the site.";

      build-servers = mkOption {
        type = attrsOf (submodule buildServerOpts);
        description =
          "List of hosts to be used as build servers for the local site.";
        default = { };
        example = {
          my-build-host = {
            port = 22;
            systems = [ "i686-linux" "x86_64-linux" ];
            build-user = "my-builder";
          };
        };
      };

      local-networks = mkOption {
        type = listOf str;
        description = "List of networks to consider local at this site.";
        default = [ ];
      };

      mail-server = mkOption {
        type = str;
        description = "Hostname of the mail server to use for this site.";
      };
    };
  };

  buildServerOpts = { hostname, ... }: {
    options = with types; {
      port = mkOption {
        type = port;
        description = "SSH port at which to contact the server.";
        default = 22;
      };

      systems = mkOption {
        type = listOf str;
        description =
          "A list of systems for which this build server can build.";
        default = [ "i686-linux" "x86_64-linux" ];
      };

      max-jobs = mkOption {
        type = int;
        description = "Max build allowed per-system.";
        default = 1;
      };

      speed-factor = mkOption {
        type = int;
        description = "Weight to give this server, i.e. it's relative speed.";
        default = 1;
      };

      supported-features = mkOption {
        type = listOf str;
        description = "List of features supported by this server.";
        default = [ ];
      };

      build-user = mkOption {
        type = str;
        description = "User as which to run distributed builds.";
        default = "nix-site-builder";
      };
    };
  };

in {
  options.fudo.sites = mkOption {
    type = with types; attrsOf (submodule siteOpts);
    description = "Site configurations for all sites known to the system.";
    default = { };
  };

  config = {
    networking.firewall.allowedTCPPorts =
      mkIf site-cfg.enable-ssh-backdoor [ site-cfg.dropbear-ssh-port ];

    systemd = mkIf site-cfg.enable-ssh-backdoor {
      sockets = {
        dropbear-deploy = {
          wantedBy = [ "sockets.target" ];
          socketConfig = {
            ListenStream = "0.0.0.0:${toString site-cfg.dropbear-ssh-port}";
            Accept = true;
          };
          unitConfig = { restartIfChanged = true; };
        };
      };

      services = {
        dropbear-deploy-init = {
          wantedBy = [ "multi-user.target" ];
          script = ''
            if [ ! -d /etc/dropbear ]; then
              mkdir /etc/dropbear
              chmod 700 /etc/dropbear
            fi

            if [ ! -f ${site-cfg.dropbear-rsa-key-path} ]; then
              ${pkgs.dropbear}/bin/dropbearkey -t rsa -f ${site-cfg.dropbear-rsa-key-path}
              ${pkgs.coreutils}/bin/chmod 0400 ${site-cfg.dropbear-rsa-key-path}
            fi

            if [ ! -f ${site-cfg.dropbear-ecdsa-key-path} ]; then
              ${pkgs.dropbear}/bin/dropbearkey -t ecdsa -f ${site-cfg.dropbear-ecdsa-key-path}
              ${pkgs.coreutils}/bin/chmod 0400 ${site-cfg.dropbear-ecdsa-key-path}
            fi
          '';
        };

        "dropbear-deploy@" = {
          description =
            "Per-connection service for deployment, using dropbear.";
          requires = [ "dropbear-deploy-init.service" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart =
              "${pkgs.dropbear}/bin/dropbear -F -i -w -m -j -k -r ${site-cfg.dropbear-rsa-key-path} -r ${site-cfg.dropbear-ecdsa-key-path}";
            ExecReload = "${pkgs.utillinux}/bin/kill -HUP $MAINPID";
            StandardInput = "socket";
          };
        };
      };
    };
  };
}
