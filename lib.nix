{ pkgs, ... }:

{
  dns = import ./lib/lib/dns.nix { inherit pkgs; };
  fs = import ./lib/lib/filesystem.nix { inherit pkgs; };
  ip = import ./lib/lib/ip.nix { inherit pkgs; };
  lisp = import ./lib/lib/lisp.nix { inherit pkgs; };
  network = import ./lib/lib/network.nix { inherit pkgs; };
  passwd = import ./lib/lib/passwd.nix { inherit pkgs; };
  text = import ./lib/lib/text.nix { inherit pkgs; };
}
