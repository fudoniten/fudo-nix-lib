# THROW THIS AWAY, NOT USED

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.hosts.local-network;

  # FIXME: this isn't used, is it?
  gatewayServerOpts = { ... }: {
    options = {
      enable = mkEnableOption "Turn this host into a network gateway.";

      internal-interfaces = mkOption {
        type = with types; listOf str;
        description =
          "List of internal interfaces from which to forward traffic.";
        default = [ ];
      };

      external-interface = mkOption {
        type = types.str;
        description =
          "Interface facing public internet, to which traffic is forwarded.";
      };

      external-tcp-ports = mkOption {
        type = with types; listOf port;
        description = "List of TCP ports to open to the outside world.";
        default = [ ];
      };

      external-udp-ports = mkOption {
        type = with types; listOf port;
        description = "List of UDP ports to open to the outside world.";
        default = [ ];
      };
    };
  };

  dnsOverHttpsProxy = {
    options = {
      enable = mkEnableOption "Enable a DNS-over-HTTPS proxy server.";

      listen-port = mkOption {
        type = types.port;
        description = "Port on which to listen for DNS requests.";
        default = 53;
      };

      upstream-dns = mkOption {
        type = with types; listOf str;
        description = "List of DoH DNS servers to use for recursion.";
        default = [ ];
      };

      bootstrap-dns = mkOption {
        type = types.str;
        description = "DNS server used to bootstrap the proxy server.";
        default = "1.1.1.1";
      };
    };
  };

  networkDhcpServerOpts = mkOption {
    options = {
      enable = mkEnableOption "Enable local DHCP server.";

      dns-servers = mkOption {
        type = with types; listOf str;
        description = "List of DNS servers for clients to use.";
        default = [ ];
      };

      listen-interfaces = mkOption {
        type = with types; listOf str;
        description = "List of interfaces on which to serve DHCP requests.";
        default = [ ];
      };

      server-ip = mkOption {
        type = types.str;
        description = "IP address of the server host.";
      };
    };
  };

  networkServerOpts = {
    options = {
      enable = mkEnableOption "Enable local networking server (DNS & DHCP).";

      domain = mkOption {
        type = types.str;
        description = "Local network domain which this host will serve.";
      };

      dns-listen-addrs = mkOption {
        type = with types; listOf str;
        description = "List of IP addresses on which to listen for requests.";
        default = [ ];
      };

      dhcp = mkOption {
        type = types.submodule networkDhcpServerOpts;
        description = "Local DHCP server options.";
      };
    };
  };

in {
  options.fudo.hosts.local-network = with types; {
    recursive-resolvers = mkOption {
      type = listOf str;
      description = "DNS server to use for recursive lookups.";
      example = "1.2.3.4 port 53";
    };

    gateway-server = mkOption {
      type = submodule gatewayServerOpts;
      description = "Gateway server options.";
    };

    dns-over-https-proxy = mkOption {
      type = submodule dnsOverHttpsProxy;
      description = "DNS-over-HTTPS proxy server.";
    };

    networkServerOpts = mkOption {
      type = submodule networkServerOpts;
      description = "Networking (DNS & DHCP) server for a local network.";
    };
  };

  config = {
    fudo.secure-dns-proxy = mkIf cfg.dns-over-https-proxy.enable {
      enable = true;
      port = cfg.dns-over-https-proxy.listen-port;
      upstream-dns = cfg.dns-over-https-proxy.upstream-dns;
      bootstrap-dns = cfg.dns-over-https-proxy.bootstrap-dns;
      listen-ips = cfg.dns-over-https-proxy.listen-ips;
    };
  };
}
