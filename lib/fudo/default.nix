{ config, lib, pkgs, ... }:

with lib; {
  imports = [
    ./auth

    ./acme-certs.nix
    ./adguard-dns-proxy.nix
    ./authentication.nix
    ./deploy.nix
    ./dns.nix
    ./domains.nix
    ./git.nix
    ./global.nix
    ./grafana.nix
    ./hosts.nix
    ./host-filesystems.nix
    ./local-network.nix
    ./mail.nix
    ./mail-container.nix
    ./minecraft-clj.nix
    ./minecraft-server.nix
    ./nexus.nix
    ./node-exporter.nix
    ./password.nix
    ./postgres.nix
    ./prometheus.nix
    ./secrets.nix
    ./secure-dns-proxy.nix
    ./sites.nix
    ./slynk.nix
    ./ssh.nix
    ./system.nix
    ./system-networking.nix
    ./users.nix
    ./vpn.nix
    ./webmail.nix
    ./wireless-networks.nix
    ./zones.nix
  ];
}
