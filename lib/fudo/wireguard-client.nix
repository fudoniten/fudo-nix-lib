{ config, lib, pkgs, ... }:

with lib;
let

in {
  options.fudo.wireguard-client = with types; {
    enable = mkEnableOption "Enable WireGuard client on this host.";

    server = {
      ip = {
        type = str;
        description = "IP address of the WireGuard server.";
      };

      port = {
        type = port;
        description = "Port on which to contact WireGuard server.";
        default = 51820;
      };

      public-key = {
        type = str;
        description = "Server public key.";
      };
    };

    assigned-ip = mkOption {
      type = str;
      description = "IP assigned to the local host.";
    };

    private-key-file = mkOption {
      type = str;
      description = "Path (on the host) to the host WireGuard private key.";
    };

    listen-port = mkOption {
      type = port;
      description = "Port on which to listen for incoming connections.";
      default = 51820;
    };

    wireguard-interface = mkOption {
      type = str;
      description = "Name of the created WireGuard interface.";
      default = "wgclient0";
    };

    managed-subnet = mkOption {
      type = str;
      description = "Subnet to route to WireGuard. 0.0.0.0/0 will send all traffic to it.";
    };
  };

  config = {
    networking = {
      firewall.allowedUDPPorts = [ cfg.listen-port ];

      wireguard.interfaces.${cfg.wireguard-interface} = {
        ips = [ "${cfg.assigned-ip}/32" ];
        listen-port = cfg.listen-port;
        private-key-file = cfg.private-key-file;
        peers = [{
          publicKey = cfg.server.public-key;
          allowedIPs = [ cfg.managed-subnet ];
          endpoint = "${cfg.server.ip}:${cfg.server.port}";
          persistentKeepalive = 25;
        }];
      };
    };
  };
}
