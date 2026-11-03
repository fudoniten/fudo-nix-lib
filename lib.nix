{ pkgs, ... }:

{
  fs = import ./lib/lib/filesystem.nix { inherit pkgs; };
  ip = import ./lib/lib/ip.nix { inherit pkgs; };
  network = import ./lib/lib/network.nix { inherit pkgs; };
  passwd = import ./lib/lib/passwd.nix { inherit pkgs; };
}
