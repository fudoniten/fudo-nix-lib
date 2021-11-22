{
  description = "Fudo Nix Helper Functions";

  outputs = { self, ... }: {
    overlay = import ./overlay.nix;

    nixosModule = import ./module.nix;

    lib = import ./lib.nix;
  };
}
