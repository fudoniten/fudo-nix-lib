{ config, lib, ... }:

with lib;
let
  hostname = config.instance.hostname;
  site-name = config.fudo.hosts.${hostname}.site;

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

      private-network = mkOption {
        type = nullOr str;
        description = "Network of the local site.";
        default = null;
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

      log-access-users = mkOption {
        type = listOf str;
        description =
          "List of users who should have access to systemd journal logs on all hosts at this site.";
        default = [ ];
      };

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
        description =
          "SSH pubkeys authorized for unattended deployment as root across this site.";
        default = null;
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

      local-gateway = mkOption {
        type = nullOr str;
        description =
          "If this is a NAT site, this should point to the host acting as network gateway.";
        default = null;
      };
      nexus = {
        public-domains = mkOption {
          type = listOf str;
          description = "Nexus domains to which hosts in this domain belong.";
          default = [ ];
        };

        private-domains = mkOption {
          type = listOf str;
          description =
            "Nexus private domains to which hosts in this domain belong.";
          default = [ ];
        };

        tailscale-domains = mkOption {
          type = listOf str;
          description =
            "Nexus tailscale domains to which hosts in this domain belong.";
          default = [ ];
        };
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

  config = { };
}
