{ config, lib, pkgs, ... }:

{
  imports = [
    ./chute.nix
    ./cl-gemini.nix
  ];
}
