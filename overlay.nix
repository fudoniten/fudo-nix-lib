(final: prev:
  with builtins; {
    lib = prev.lib // (import ./lib.nix { pkgs = prev; });
  })
