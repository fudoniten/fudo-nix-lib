{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.wireguard;

  peerOpts = { name, ... }: {
    options = {
      public-key = mkOption {
        type = str;
        description = "Peer public key.";
      };

      assigned-ip = mkOption {
        type = str;
        description = "IP assigned to this peer.";
      };
    };
  };

in {
  options.fudo.wireguard = with types; {
    enable = mkEnableOption "Enable WireGuard server.";

    network = mkOption {
      type = str;
      description = "WireGuard managed IP subnet.";
      default = "172.16.0.0/16";
    };

    routed-network = mkOption {
      type = str;
      description = "Subnet of larger network for which we act as a gateway.";
      default = "172.16.16.0/20";
    };

    peers = mkOption {
      type = attrsOf (submodule peerOpts);
      description = "Map of peer to peer options.";
      default = { };
    };

    listen-port = mkOption {
      type = port;
      description = "Port on which to listen for incoming connections.";
      default = 51820;
    };

    private-key-file = mkOption {
      type = str;
      description = "Path (on the host) to the host WireGuard private key.";
    };

    wireguard-interface = mkOption {
      type = str;
      description = "Name of the created WireGuard interface.";
      default = "wgnet0";
    };

    external-interface = mkOption {
      type = str;
      description = "Name of the host public-facing interface.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = all (peerOpts:
          pkgs.lib.ip.ipv4OnNetwork peerOpts.assigned-ip cfg.network)
          (attrValues cfg.peers);
        message = "Peer IPs must be on the assigned network.";
      }
    ];

    networking = {
      firewall.allowedUDPPorts = [ cfg.listen-port ];
      wireguard.interfaces.${cfg.wireguard-interface} = {
        ips = [ cfg.network ];
        listenPort = cfg.listen-port;
        postSetup =
          "${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${cfg.network} -o ${cfg.external-interface} -j MASQUERADE";
        postShutdown =
          "${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${cfg.network} -o ${cfg.external-interface} -j MASQUERADE";

        privateKeyFile = cfg.private-key-file;

        peers = mapAttrs (_: peerOpts: {
          public-key = peerOpts.public-key;
          allowedIPs = [ "${peerOpts.assigned-ip}/32" ];
        }) cfg.peers;
      };
    };
  };
}
