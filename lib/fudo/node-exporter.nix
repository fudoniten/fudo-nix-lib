{ lib, config, pkgs, ... }:

with lib;
let
  inherit (lib.strings) concatStringsSep;

  cfg = config.fudo.metrics.node-exporter;

  allow-network = network: "allow ${network};";

  local-networks = config.instance.local-networks;

in {
  options.fudo.metrics.node-exporter = with types; {
    enable = mkEnableOption "Enable a Prometheus node exporter with some reasonable settings.";

    hostname = mkOption {
      type = str;
      description = "Hostname from which to export statistics.";
    };

    user = mkOption {
      type = str;
      description = "User as which to run the node exporter job.";
      default = "node-exporter";
    };

    private-network = mkEnableOption "Network is private.";
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
    };

    services = {
      # This'll run an exporter at localhost:9100
      prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
        listenAddress = "127.0.0.1";
        port = 9100;
        user = cfg.user;
      };

      # ...And this'll expose the above to the outside world, or at least the
      # list of trusted networks, with SSL protection.
      nginx = {
        enable = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;

        virtualHosts."${cfg.hostname}" = {
          enableACME = ! cfg.private-network;
          forceSSL = ! cfg.private-network;

          locations."/metrics/node" = {
            extraConfig = ''
              ${concatStringsSep "\n" (map allow-network local-networks)}
              allow 127.0.0.0/16;
              deny all;

              proxy_set_header X-Real-IP $remote_addr;
            '';

            proxyPass = "http://127.0.0.1:9100/metrics";
          };
        };
      };
    };
  };
}
