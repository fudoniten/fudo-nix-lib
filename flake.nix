{
  description = "Fudo Nix Helper Functions";

  outputs = { self, ... }: {
    overlay = import ./overlay.nix;

    lib = import ./lib.nix;
  };
}
