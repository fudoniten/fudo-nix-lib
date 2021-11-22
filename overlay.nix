(final: prev: with builtins; {
  lib = let
    pkgs = prev;
  in
    pkgs.lib // (import ./lib.nix { inherit pkgs; });
})
