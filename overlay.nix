(final: prev: with builtins; {
  lib = let
    pkgs = prev;
    lib = prev.lib;
  in
    lib // {
      ip = import ./lib/ip.nix { inherit pkgs; };
      dns = import ./lib/dns.nix { inherit pkgs; };
      passwd = import ./lib/passwd.nix { inherit pkgs; };
      lisp = import ./lib/lisp.nix { inherit pkgs; };
      network = import ./lib/network.nix { inherit pkgs; };
      fs = import ./lib/filesystem.nix { inherit pkgs; };
    };
})
