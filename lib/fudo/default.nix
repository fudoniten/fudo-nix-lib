{ config, lib, pkgs, ... }:

with lib; {
  imports = [
    ./auth

    ./acme-certs.nix
    ./adguard-dns-proxy.nix
    ./deploy.nix
    ./domains.nix
    ./hosts.nix
    ./host-filesystems.nix
    ./minecraft-server.nix
    ./minecraft-server-multi.nix
    ./nebula.nix
    ./nexus.nix
    ./node-exporter.nix
    ./password.nix
    ./prometheus.nix
    ./secrets.nix
    ./secure-dns-proxy.nix
    ./sites.nix
    ./slynk.nix
    ./ssh.nix
    ./system.nix
    ./system-networking.nix
    ./users.nix
    ./webmail.nix
    ./wireless-networks.nix
    ./zones.nix
  ];
}
