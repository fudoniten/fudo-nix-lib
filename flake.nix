{
  description = "Fudo Nix Helper Functions";

  outputs = { self, nixpkgs, ... }: {
    overlay = import ./overlay.nix;
  };
}
