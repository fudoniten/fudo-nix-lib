{ lib, config, pkgs, ... }:

{
  imports = [
    ./instance.nix

    ./fudo
  ];
}
