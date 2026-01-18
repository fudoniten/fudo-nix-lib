# DNS Services Module Group
#
# This module group provides DNS server and client infrastructure:
# - NSD (authoritative DNS server)
# - PowerDNS (authoritative DNS with database backend)
# - Local network services (DHCP + dnsmasq for dynamic DNS)
# - DNS client configuration
# - DNS proxy services (AdGuard, secure DNS)
#
# Dependencies: core (for zones, domains, hosts)
# Optional: messaging (for backplane DNS service)

{ ... }: {
  imports = [
    ../lib/fudo/adguard-dns-proxy.nix
    ../lib/fudo/backplane-service/dns.nix
    ../lib/fudo/client/dns.nix
    ../lib/fudo/dns.nix
    ../lib/fudo/local-network.nix
    ../lib/fudo/nsd.nix
    ../lib/fudo/powerdns.nix
    ../lib/fudo/secure-dns-proxy.nix
  ];
}
