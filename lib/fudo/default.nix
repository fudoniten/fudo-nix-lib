{ config, lib, pkgs, ... }:

with lib; {
  imports = [
    ./auth

    ./backplane-service/dns.nix

    ./acme-certs.nix
    ./adguard-dns-proxy.nix
    ./authentication.nix
    ./backplane.nix
    ./chat.nix
    ./client/dns.nix
    ./deploy.nix
    ./distributed-builds.nix
    ./dns.nix
    ./domains.nix
    ./garbage-collector.nix
    ./git.nix
    ./global.nix
    ./grafana.nix
    ./hosts.nix
    ./host-filesystems.nix
    ./initrd-network.nix
    ./ipfs.nix
    ./jabber.nix
    # ./kdc.nix
    ./ldap.nix
    ./local-network.nix
    ./mail.nix
    ./mail-container.nix
    ./minecraft-clj.nix
    ./minecraft-server.nix
    ./netinfo-email.nix
    ./node-exporter.nix
    ./nsd.nix
    ./password.nix
    ./postgres.nix
    ./powerdns.nix
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
    # ./wireguard.nix
    # ./wireguard-client.nix
    ./wireless-networks.nix
    ./zones.nix
  ];
}
