{ lib, config, pkgs, ... }:

{
  imports = [
    ./instance.nix

    ./fudo

    ./informis
  ];
}
