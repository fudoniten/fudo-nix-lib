{ config, lib, pkgs, ... }:

with lib;
let
  user = import ./types/user.nix { inherit lib; };
  host = import ./types/host.nix { inherit lib; };

in {
  options.instance = with lib.types; {
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
      description =
        "Timestamp associated with the build. Used for e.g. DNS serials.";
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

    local-zone = mkOption {
      type = nullOr str;
      description = "Zone name of the current local host.";
      default = null;
    };

    local-admins = mkOption {
      type = listOf str;
      description =
        "List of users who should have admin access to the local host.";
    };

    local-groups = mkOption {
      type = attrsOf (submodule user.groupOpts);
      description = "List of groups which should be created on the local host.";
    };

    local-hosts = mkOption {
      type = attrsOf (submodule host.hostOpts);
      description =
        "List of hosts that should be considered local to the current host.";
    };

    local-users = mkOption {
      type = attrsOf (submodule user.userOpts);
      description = "List of users who should have access to the local host";
    };

    local-networks = mkOption {
      type = listOf str;
      description =
        "Networks which are considered local to this host, site, or domain.";
    };

    service-home = mkOption {
      type = str;
      description = "Path to runtime home directories for services.";
      default = "/run/service";
    };

    build-seed = mkOption {
      type = str;
      description = "Seed used to generate configuration.";
    };
  };

  config = {
    systemd.tmpfiles.rules =
      [ "d ${config.instance.service-home} 755 root root - -" ];
  };
}
