{ config, lib, pkgs, ... }:

with lib;
let
  mapOptional = f: val: if (val != null) then (f val) else null;

  host = import ../types/host.nix { inherit lib; };

  hostname = config.instance.hostname;

in {
  options.fudo.hosts = with types;
    mkOption {
      type = attrsOf (submodule host.hostOpts);
      description = "Host configurations for all hosts known to the system.";
      default = { };
    };

  config = let
    hostname = config.instance.hostname;
    host-cfg = config.fudo.hosts.${hostname};
    site-name = host-cfg.site;
    site = config.fudo.sites.${site-name};
    domain-name = host-cfg.domain;
    domain = config.fudo.domains.${domain-name};
    has-build-servers = (length (attrNames site.build-servers)) > 0;
    has-build-keys = (length host-cfg.build-pubkeys) > 0;

  in {
    security.sudo.extraConfig = ''
      # I get it, I get it
      Defaults lecture = never
    '';

    networking = {
      hostName = config.instance.hostname;
      domain = domain-name;
      nameservers = site.nameservers;
      # This will cause a loop on the gateway itself
      #defaultGateway = site.gateway-v4;
      #defaultGateway6 = site.gateway-v6;

      firewall = mkIf ((length host-cfg.external-interfaces) > 0) {
        enable = true;
        allowedTCPPorts = [ 22 2112 ]; # Make sure _at least_ SSH is allowed
        trustedInterfaces =
          let all-interfaces = attrNames config.networking.interfaces;
          in subtractLists host-cfg.external-interfaces all-interfaces;
      };

      hostId =
        mkIf (host-cfg.machine-id != null) (substring 0 8 host-cfg.machine-id);
    };

    environment = {
      etc = {
        # NixOS generates a stupid hosts file, just force it
        hosts = let
          host-entries = mapAttrsToList
            (ip: hostnames: "${ip} ${concatStringsSep " " hostnames}")
            config.fudo.system.hostfile-entries;
        in mkForce {
          text = ''
            127.0.0.1 ${hostname}.${domain-name} ${hostname} localhost
            127.0.0.2 ${hostname} localhost
            ::1 ${hostname}.${domain-name} ${hostname} localhost
            ${concatStringsSep "\n" host-entries}
          '';
          user = "root";
          group = "root";
          mode = "0444";
        };

        machine-id = mkIf (host-cfg.machine-id != null) {
          text = host-cfg.machine-id;
          user = "root";
          group = "root";
          mode = "0444";
        };

        current-system-packages.text = with builtins;
          let
            packages = map (p: "${p.name}") config.environment.systemPackages;
            sorted-unique = sort lessThan (unique packages);
          in ''
            ${concatStringsSep "\n" sorted-unique}
          '';
      };

      systemPackages = with pkgs;
        mkIf (host-cfg.docker-server) [ docker nix-prefetch-docker ];
    };

    time.timeZone = site.timezone;

    krb5.libdefaults.default_realm = domain.gssapi-realm;

    services = {
      cron.mailto = domain.admin-email;
      fail2ban.ignoreIP = config.instance.local-networks;
    };

    virtualisation.docker = mkIf (host-cfg.docker-server) {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
    };

    programs.adb.enable = host-cfg.android-dev;
    users.groups.adbusers =
      mkIf host-cfg.android-dev { members = config.instance.local-admins; };

    boot.tmp.useTmpFs = host-cfg.tmp-on-tmpfs;
  };
}
