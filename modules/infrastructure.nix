# Infrastructure Services Module Group
#
# This module group provides core infrastructure and deployment services:
# - PostgreSQL database (used by mail, dns, chat, etc.)
# - ACME/Let's Encrypt certificate management
# - Deployment orchestration (deploy-rs integration)
# - Distributed Nix builds
# - Encrypted filesystem management
# - Network interface configuration
# - VPN services (OpenVPN and WireGuard)
# - Wireless network configuration
# - Garbage collection/cleanup
#
# Dependencies: core (for hosts, sites, secrets)

{ ... }: {
  imports = [
    ../lib/fudo/acme-certs.nix
    ../lib/fudo/deploy.nix
    ../lib/fudo/distributed-builds.nix
    ../lib/fudo/garbage-collector.nix
    ../lib/fudo/host-filesystems.nix
    ../lib/fudo/postgres.nix
    ../lib/fudo/system-networking.nix
    ../lib/fudo/vpn.nix
    ../lib/fudo/wireless-networks.nix
    # ../lib/fudo/wireguard.nix         # Commented out in original default.nix
    # ../lib/fudo/wireguard-client.nix  # Commented out in original default.nix
  ];
}
