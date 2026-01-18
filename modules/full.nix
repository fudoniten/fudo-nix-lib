# Full Module Collection (Backwards Compatibility)
#
# This module imports all available module groups, providing the same
# behavior as the previous monolithic module.nix. Use this for hosts
# that need access to all services, or during migration.
#
# For new deployments, prefer importing only the specific module groups
# your host needs (e.g., core + dns + monitoring).

{ ... }: {
  imports = [
    # Core configuration (required)
    ./core.nix

    # Service module groups
    ./auth.nix
    ./dns.nix
    ./infrastructure.nix
    ./mail.nix
    ./messaging.nix
    ./monitoring.nix
    ./services.nix

    # Additional modules not in groups
    ../lib/fudo/global.nix
    ../lib/informis
  ];
}
