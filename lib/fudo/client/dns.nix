{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.fudo.client.dns;

  ssh-key-files =
    map (host-key: host-key.path) config.services.openssh.hostKeys;

  ssh-key-args = concatStringsSep " " (map (file: "-f ${file}") ssh-key-files);

in {
  options.fudo.client.dns = {
    ipv4 = mkOption {
      type = types.bool;
      default = true;
      description = "Report host external IPv4 address to Fudo DynDNS server.";
    };

    ipv6 = mkOption {
      type = types.bool;
      default = true;
      description = "Report host external IPv6 address to Fudo DynDNS server.";
    };

    sshfp = mkOption {
      type = types.bool;
      default = true;
      description = "Report host SSH fingerprints to the Fudo DynDNS server.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain under which this host is registered.";
      default = "fudo.link";
    };

    server = mkOption {
      type = types.str;
      description = "Backplane DNS server to which changes will be reported.";
      default = "backplane.fudo.org";
    };

    password-file = mkOption {
      type = types.str;
      description = "File containing host password for backplane.";
      example = "/path/to/secret.passwd";
    };

    frequency = mkOption {
      type = types.str;
      description =
        "Frequency at which to report the local IP(s) to backplane.";
      default = "*:0/15";
    };

    user = mkOption {
      type = types.str;
      description =
        "User as which to run the client script (must have access to password file).";
      default = "backplane-dns-client";
    };

    external-interface = mkOption {
      type = with types; nullOr str;
      description =
        "Interface with which this host communicates with the larger internet.";
      default = null;
    };
  };

  config = {

    users = {
      users = {
        "${cfg.user}" = {
          isSystemUser = true;
          createHome = true;
          home = "/run/home/${cfg.user}";
          group = cfg.user;
        };
      };

      groups = {
        "${cfg.user}" = {
          members = [ cfg.user ];
        };
      };
    };

    systemd = {
      tmpfiles.rules = [
        "d /run/home 755 root - - -"
        "d /run/home/${cfg.user} 700 ${cfg.user} - - -"
      ];

      timers.backplane-dns-client = {
        enable = true;
        description = "Report local IP addresses to Fudo backplane.";
        partOf = [ "backplane-dns-client.service" ];
        wantedBy = [ "timers.target" ];
        requires = [ "network-online.target" ];
        timerConfig = { OnCalendar = cfg.frequency; };
      };

      services.backplane-dns-client-pw-file = {
        enable = true;
        requiredBy = [ "backplane-dns-client.services" ];
        reloadIfChanged = true;
        serviceConfig = { Type = "oneshot"; };
        script = ''
          chmod 400 ${cfg.password-file}
          chown ${cfg.user} ${cfg.password-file}
        '';
      };

      services.backplane-dns-client = {
        enable = true;
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal";
          User = cfg.user;
          ExecStart = pkgs.writeShellScript "start-backplane-dns-client.sh" ''
            ${pkgs.backplane-dns-client}/bin/backplane-dns-client ${
              optionalString cfg.ipv4 "-4"
            } ${optionalString cfg.ipv6 "-6"} ${
              optionalString cfg.sshfp ssh-key-args
            } ${
              optionalString (cfg.external-interface != null)
              "--interface=${cfg.external-interface}"
            } --domain=${cfg.domain} --server=${cfg.server} --password-file=${cfg.password-file}
          '';
        };
        # Needed to generate SSH fingerprinst
        path = [ pkgs.openssh ];
        reloadIfChanged = true;
      };
    };
  };
}
