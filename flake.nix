{
  description = "Fudo Nix Helper Functions";

  outputs = { self, ... }: {
    overlays = rec {
      default = lib;
      lib = import ./overlay.nix;
    };

    nixosModules = rec {
      default = fudo;
      fudo = import ./module.nix;
      lib = { ... }: { config.nixpkgs.overlays = [ self.overlays.default ]; };
    };

    lib = import ./lib.nix;
  };
}
