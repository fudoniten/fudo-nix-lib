# Core Configuration Module Group
#
# This module group provides foundational configuration that all services depend on:
# - Host, site, domain, and zone definitions
# - User and group definitions
# - Secret management infrastructure
# - System-level configuration
#
# Import this module in every host configuration.

{ ... }: {
  imports = [
    ../lib/fudo/domains.nix
    ../lib/fudo/hosts.nix
    ../lib/fudo/secrets.nix
    ../lib/fudo/sites.nix
    ../lib/fudo/system.nix
    ../lib/fudo/users.nix
    ../lib/fudo/zones.nix
  ];
}
