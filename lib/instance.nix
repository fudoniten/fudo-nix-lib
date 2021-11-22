{ config, lib, pkgs, ... }:

with lib;
let
  user = import ./types/user.nix { inherit lib; };
  host = import ./types/host.nix { inherit lib; };

in {
  options.instance = with types; {
    hostname = mkOption {
      type = str;
      description = "Hostname of this specific host (without domain).";
    };

    host-fqdn = mkOption {
      type = str;
      description = "Fully-qualified name of this host.";
    };

    build-timestamp = mkOption {
      type = int;
      description = "Timestamp associated with the build. Used for e.g. DNS serials.";
    };

    local-domain = mkOption {
      type = str;
      description = "Domain name of the current local host.";
    };

    local-profile = mkOption {
      type = str;
      description = "Profile name of the current local host.";
    };

    local-site = mkOption {
      type = str;
      description = "Site name of the current local host.";
    };

    local-admins = mkOption {
      type = listOf str;
      description = "List of users who should have admin access to the local host.";
    };

    local-groups = mkOption {
      type = attrsOf (submodule user.groupOpts);
      description = "List of groups which should be created on the local host.";
    };

    local-hosts = mkOption {
      type = attrsOf (submodule host.hostOpts);
      description = "List of hosts that should be considered local to the current host.";
    };

    local-users = mkOption {
      type = attrsOf (submodule user.userOpts);
      description = "List of users who should have access to the local host";
    };

    local-networks = mkOption {
      type = listOf str;
      description = "Networks which are considered local to this host, site, or domain.";
    };

    build-seed = mkOption {
      type = str;
      description = "Seed used to generate configuration.";
    };
  };

  config = let
    local-host = config.instance.hostname;
    local-domain = config.fudo.hosts.${local-host}.domain;
    local-site = config.fudo.hosts.${local-host}.site;

    host = config.fudo.hosts.${local-host};

    host-user-list = host.local-users;
    domain-user-list = config.fudo.domains."${local-domain}".local-users;
    site-user-list = config.fudo.sites."${local-site}".local-users;
    local-users =
      getAttrs (host-user-list ++ domain-user-list ++ site-user-list) config.fudo.users;

    host-admin-list = host.local-admins;
    domain-admin-list = config.fudo.domains."${local-domain}".local-admins;
    site-admin-list = config.fudo.sites."${local-site}".local-admins;
    local-admins = host-admin-list ++ domain-admin-list ++ site-admin-list;

    host-group-list = host.local-groups;
    domain-group-list = config.fudo.domains."${local-domain}".local-groups;
    site-group-list = config.fudo.sites."${local-site}".local-groups;
    local-groups =
      getAttrs (host-group-list ++ domain-group-list ++ site-group-list)
        config.fudo.groups;

    local-hosts =
      filterAttrs (host: hostOpts: hostOpts.site == local-site) config.fudo.hosts;

    local-networks =
      host.local-networks ++
      config.fudo.domains.${local-domain}.local-networks ++
      config.fudo.sites.${local-site}.local-networks;

    local-profile = host.profile;

    host-fqdn = "${config.instance.hostname}.${local-domain}";

  in {
    instance = {
      inherit
        host-fqdn
        local-domain
        local-site
        local-users
        local-admins
        local-groups
        local-hosts
        local-profile
        local-networks;
    };
  };
}
