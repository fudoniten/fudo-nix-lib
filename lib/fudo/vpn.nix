{ pkgs, lib, config, ... }:

with lib;
let
  cfg = config.fudo.vpn;

  generate-pubkey-pkg = name: privkey:
    pkgs.runCommand "wireguard-${name}-pubkey" {
      WIREGUARD_PRIVATE_KEY = privkey;
    } ''
      mkdir $out
      PUBKEY=$(echo $WIREGUARD_PRIVATE_KEY | ${pkgs.wireguard-tools}/bin/wg pubkey)
      echo $PUBKEY > $out/pubkey.key
    '';

  generate-client-config = privkey-file: server-pubkey: network: server-ip: listen-port: dns-servers: ''
      [Interface]
      Address = ${ip.networkMinIp network}
      PrivateKey = ${fileContents privkey-file}
      ListenPort = ${toString listen-port}
      DNS = ${concatStringsSep ", " dns-servers}

      [Peer]
      PublicKey = ${server-pubkey}
      Endpoint = ${server-ip}:${toString listen-port}
      AllowedIps = 0.0.0.0/0, ::/0
      PersistentKeepalive = 25
    '';

  generate-peer-entry = peer-name: peer-privkey-path: peer-allowed-ips: let
    peer-pkg = generate-pubkey-pkg "client-${peer-name}" (fileContents peer-privkey-path);
    pubkey-path = "${peer-pkg}/pubkey.key";
  in {
    publicKey = fileContents pubkey-path;
    allowedIPs = peer-allowed-ips;
  };

in {
  options.fudo.vpn = with types; {
    enable = mkEnableOption "Enable Fudo VPN";

    network = mkOption {
      type = str;
      description = "Network range to assign this interface.";
      default = "10.100.0.0/16";
    };

    private-key-file = mkOption {
      type = str;
      description = "Path to the secret key (generated with wg [genkey/pubkey]).";
      example = "/path/to/secret.key";
    };

    listen-port = mkOption {
      type = port;
      description = "Port on which to listen for incoming connections.";
      default = 51820;
    };

    dns-servers = mkOption {
      type = listOf str;
      description = "A list of dns servers to pass to clients.";
      default = ["1.1.1.1" "8.8.8.8"];
    };

    server-ip = mkOption {
      type = str;
      description = "IP of this WireGuard server.";
    };

    peers = mkOption {
      type = attrsOf str;
      description = "A map of peers to shared private keys.";
      default = {};
      example = {
        peer0 = "/path/to/priv.key";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.etc = let
      peer-data = imap1 (i: peer:{
        name = peer.name;
        privkey-path = peer.privkey-path;
        network-range = let
          base = ip.intToIpv4
            ((ip.ipv4ToInt (ip.getNetworkBase cfg.network)) + (i * 256));
        in "${base}/24";
      }) (mapAttrsToList (name: privkey-path: {
        name = name;
        privkey-path = privkey-path;
      }) cfg.peers);

      server-pubkey-pkg = generate-pubkey-pkg "server-pubkey" (fileContents cfg.private-key-file);

      server-pubkey = fileContents "${server-pubkey-pkg}/pubkey.key";

    in listToAttrs
      (map (peer: nameValuePair "wireguard/clients/${peer.name}.conf" {
        mode = "0400";
        user = "root";
        group = "root";
        text = generate-client-config
          peer.privkey-path
          server-pubkey
          peer.network-range
          cfg.server-ip
          cfg.listen-port
          cfg.dns-servers;
      }) peer-data);

    networking.wireguard = {
      enable = true;
      interfaces.wgtun0 = {
        generatePrivateKeyFile = false;
        ips = [ cfg.network ];
        listenPort = cfg.listen-port;
        peers = mapAttrsToList
          (name: private-key: generate-peer-entry name private-key ["0.0.0.0/0" "::/0"])
          cfg.peers;
        privateKeyFile = cfg.private-key-file;
      };
    };
  };
}
