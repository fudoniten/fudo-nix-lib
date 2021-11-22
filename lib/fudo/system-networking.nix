{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.system;

  portMappingOpts = { name, ... }: {
    options = with types; {
      internal-port = mkOption {
        type = port;
        description = "Port on localhost to recieve traffic";
      };
      external-port = mkOption {
        type = port;
        description = "External port on which to listen for traffic.";
      };
      protocols = mkOption {
        type = listOf str;
        description =
          "Protocols for which to forward ports. Default is tcp-only.";
        default = [ "tcp" ];
      };
    };
  };

in {
  options.fudo.system = with types; {
    internal-port-map = mkOption {
      type = attrsOf (submodule portMappingOpts);
      description =
        "Sets of external ports to internal (i.e. localhost) ports to forward.";
      default = { };
      example = {
        sshmap = {
          internal-port = 2222;
          external-port = 22;
          protocol = "udp";
        };
      };
    };

    # DO THIS MANUALLY since NixOS sux at making a reasonable /etc/hosts
    hostfile-entries = mkOption {
        type = attrsOf (listOf str);
        description = "Map of extra IP addresses to hostnames for /etc/hosts";
        default = {};
        example = {
            "10.0.0.3" = [ "my-host" "my-host.my.domain" ];
        };
    };
  };

  config = mkIf (cfg.internal-port-map != { }) {
    # FIXME: FUCK ME THIS IS WAY HARDER THAN IT SHOULD BE
    # boot.kernel.sysctl = mkIf (cfg.internal-port-map != { }) {
    #   "net.ipv4.conf.all.route_localnet" = "1";
    # };

    # fudo.system.services.forward-internal-ports = let
    #   ip-line = op: src-port: target-port: protocol: ''
    #     ${ipt} -t nat -${op} PREROUTING -p ${protocol} --dport ${
    #       toString src-port
    #     } -j REDIRECT --to-ports ${toString target-port}
    #     ${ipt} -t nat -${op} OUTPUT -p ${protocol} -s lo --dport ${
    #       toString src-port
    #     } -j REDIRECT --to-ports ${toString target-port}
    #   '';

    #   ip-forward-line = ip-line "I";

    #   ip-unforward-line = ip-line "D";

    #   traceOut = obj: builtins.trace obj obj;

    #   concatMapAttrsToList = f: attrs: concatLists (mapAttrsToList f attrs);

    #   portmap-entries = concatMapAttrsToList (name: opts:
    #     map (protocol: {
    #       src = opts.external-port;
    #       target = opts.internal-port;
    #       protocol = protocol;
    #     }) opts.protocols) cfg.internal-port-map;

    #   make-entries = f: { src, target, protocol, ... }: f src target protocol;

    #   forward-entries = map (make-entries ip-forward-line) portmap-entries;

    #   unforward-entries = map (make-entries ip-unforward-line) portmap-entries;

    #   forward-ports-script = pkgs.writeShellScript "forward-internal-ports.sh"
    #     (concatStringsSep "\n" forward-entries);

    #   unforward-ports-script =
    #     pkgs.writeShellScript "unforward-internal-ports.sh"
    #     (concatStringsSep "\n"
    #       (map (make-entries ip-unforward-line) portmap-entries));
    # in {
    #   wantedBy = [ "multi-user.target" ];
    #   after = [ "firewall.service" "nat.service" ];
    #   type = "oneshot";
    #   description = "Rules for forwarding external ports to local ports.";
    #   execStart = "${forward-ports-script}";
    #   execStop = "${unforward-ports-script}";
    #   requiredCapabilities =
    #     [ "CAP_DAC_READ_SEARCH" "CAP_NET_ADMIN" "CAP_NET_RAW" ];
    # };

    # networking.firewall = let
    #   iptables = "ip46tables";
    #   ip-forward-line = protocols: internal: external:
    #     concatStringsSep "\n" (map (protocol: ''
    #       ${iptables} -t nat -I PREROUTING -p ${protocol} --dport ${
    #         toString external
    #       } -j REDIRECT --to-ports ${toString internal}
    #       ${iptables} -t nat -I OUTPUT -s lo -p ${protocol} --dport ${
    #         toString external
    #       } -j REDIRECT --to-ports ${toString internal}
    #     '') protocols);

    #   ip-unforward-line = protocols: internal: external:
    #     concatStringsSep "\n" (map (protocol: ''
    #       ${iptables} -t nat -D PREROUTING -p ${protocol} --dport ${
    #         toString external
    #       } -j REDIRECT --to-ports ${toString internal}
    #       ${iptables} -t nat -D OUTPUT -s lo -p ${protocol} --dport ${
    #         toString external
    #       } -j REDIRECT --to-ports ${toString internal}
    #     '') protocols);
    # in {
    #   enable = true;

    #   extraCommands = concatStringsSep "\n" (mapAttrsToList (name: opts:
    #     ip-forward-line opts.protocols opts.internal-port opts.external-port)
    #     cfg.internal-port-map);

    #   extraStopCommands = concatStringsSep "\n" (mapAttrsToList (name: opts:
    #     ip-unforward-line opts.protocols opts.internal-port opts.external-port)
    #     cfg.internal-port-map);
    # };

    # networking.nat.forwardPorts =
    #   let portmaps = (attrValues opts.external-port);
    #   in concatMap (opts:
    #     map (protocol: {
    #       destination = "127.0.0.1:${toString opts.internal-port}";
    #       sourcePort = opts.external-port;
    #       proto = protocol;
    #     }) opts.protocols) (attrValues cfg.internal-port-map);

    # services.xinetd = mkIf ((length (attrNames cfg.internal-port-map)) > 0) {
    #   enable = true;
    #   services = let
    #     svcs = mapAttrsToList (name: opts: opts // { name = name; })
    #       cfg.internal-port-map;
    #     svcs-protocols = concatMap
    #       (svc: map (protocol: svc // { protocol = protocol; }) svc.protocols)
    #       svcs;
    #   in map (opts: {
    #     name = opts.name;
    #     unlisted = true;
    #     port = opts.external-port;
    #     server = "${pkgs.coreutils}/bin/false";
    #     extraConfig = "redirect = localhost ${toString opts.internal-port}";
    #     protocol = opts.protocol;
    #   }) svcs-protocols;
    # };
  };
}
