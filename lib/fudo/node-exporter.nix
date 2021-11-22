{ lib, config, pkgs, ... }:

with lib;
let
  inherit (lib.strings) concatStringsSep;

  cfg = config.fudo.node-exporter;
  fudo-cfg = config.fudo.common;

  allow-network = network: "allow ${network};";

in {
  options.fudo.node-exporter = {
    enable = mkEnableOption "Enable a Prometheus node exporter with some reasonable settings.";

    hostname = mkOption {
      type = types.str;
      description = "Hostname from which to export statistics.";
    };
  };

  config = mkIf cfg.enable {
    security.acme.certs.${cfg.hostname}.email = fudo-cfg.admin-email;

    services = {
      # This'll run an exporter at localhost:9100
      prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
        listenAddress = "127.0.0.1";
        port = 9100;
        user = "node";
      };

      # ...And this'll expose the above to the outside world, or at least the
      # list of trusted networks, with SSL protection.
      nginx = {
        enable = true;

        virtualHosts."${cfg.hostname}" = {
          enableACME = true;
          forceSSL = true;

          locations."/metrics/node" = {
            extraConfig = ''
              ${concatStringsSep "\n" (map allow-network fudo-cfg.local-networks)}
              allow 127.0.0.0/16;
              deny all;

              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header Host $host;
            '';

            proxyPass = "http://127.0.0.1:9100/metrics";
          };
        };
      };
    };
  };
}
