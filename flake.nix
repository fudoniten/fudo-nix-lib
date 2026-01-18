{
  description = "Fudo Nix Helper Functions";

  outputs = { self, ... }: {
    overlays = rec {
      default = lib;
      lib = import ./overlay.nix;
    };

    nixosModules = rec {
      # Modular outputs - import only what you need
      core = import ./modules/core.nix;
      auth = import ./modules/auth.nix;
      dns = import ./modules/dns.nix;
      infrastructure = import ./modules/infrastructure.nix;
      mail = import ./modules/mail.nix;
      messaging = import ./modules/messaging.nix;
      monitoring = import ./modules/monitoring.nix;
      services = import ./modules/services.nix;

      # Full monolith - all modules (backwards compatibility)
      full = import ./modules/full.nix;

      # Backwards compatibility: default uses full module collection
      default = full;
      fudo = full;

      # Overlay-only module for nixpkgs extensions
      lib = { ... }: { config.nixpkgs.overlays = [ self.overlays.default ]; };
    };

    lib = import ./lib.nix;
  };
}
