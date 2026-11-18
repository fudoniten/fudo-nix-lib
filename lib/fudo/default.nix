{ config, lib, pkgs, ... }:

with lib; {
  imports = [
    ./auth

    ./adguard-dns-proxy.nix
    ./deploy.nix
    ./host-filesystems.nix
    ./minecraft-server.nix
    ./minecraft-server-multi.nix
    ./node-exporter.nix
    ./prometheus.nix
    ./secrets.nix
    ./slynk.nix
    ./ssh.nix
    ./system-networking.nix
    ./webmail.nix
    ./wireless-networks.nix
  ];
}
