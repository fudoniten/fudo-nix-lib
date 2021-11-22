{ config, pkgs, lib, ... }:

with lib;
{
  imports = [
    ./common.nix
    ./dns.nix
    ./jabber.nix
  ];
}
