{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;
  initrd-cfg = config.fudo.hosts.${hostname}.initrd-network;

  read-lines = filename: splitString "\n" (fileContents filename);

  concatLists = lsts: concatMap (i: i) lsts;

  gen-sshfp-records-pkg = hostname: pubkey: let
    pubkey-file = builtins.toFile "${hostname}-initrd-ssh-pubkey" pubkey;
  in pkgs.stdenv.mkDerivation {
    name = "${hostname}-initrd-ssh-firngerprint";

    phases = [ "installPhase" ];

    buildInputs = with pkgs; [ openssh ];

    installPhase = ''
      mkdir $out
      ssh-keygen -r REMOVEME -f "${pubkey-file}" | sed 's/^REMOVEME IN SSHFP //' >> $out/initrd-ssh-pubkey.sshfp
    '';
  };

  gen-sshfp-records = hostname: pubkey: let
    sshfp-record-pkg = gen-sshfp-records-pkg hostname pubkey;
  in read-lines "${sshfp-record-pkg}/initrd-ssh-pubkey.sshfp";

in {
  config = {
    boot = mkIf (initrd-cfg != null) {
      kernelParams = let
        site-name = config.instance.local-site;
        site = config.fudo.sites.${site-name};
        site-gateway = pkgs.lib.network.site-gateway config site-name;
        netmask =
          pkgs.lib.ip.maskFromV32Network site.network;
      in [
        "ip=${initrd-cfg.ip}:${site-gateway}:${netmask}:${hostname}:${initrd-cfg.interface}"
      ];
      initrd = {
        network = {
          enable = true;

          ssh = let
            admin-ssh-keys =
              concatMap (admin: config.fudo.users.${admin}.ssh-authorized-keys)
                config.instance.local-admins;
          in {
            enable = true;
            port = 22;
            authorizedKeys = admin-ssh-keys;
            hostKeys = [
              initrd-cfg.keypair.private-key-file
            ];
          };
        };
      };
    };

    fudo = {
      local-network = let
        initrd-network-hosts =
          filterAttrs
            (hostname: hostOpts: hostOpts.initrd-network != null)
            config.instance.local-hosts;
      in {
        zone-definition.hosts = mapAttrs'
          (hostname: hostOpts: nameValuePair "${hostname}-recovery" {
            ipv4-address = hostOpts.initrd-network.ip;
            description = "${hostname} initrd host";
          }) initrd-network-hosts;

        extra-records = let
          recs = (mapAttrsToList
            (hostname: hostOpts: map
              (sshfp: "${hostname} IN SSHFP ${sshfp}")
              (gen-sshfp-records hostname hostOpts.initrd-network.keypair.public-key))
            initrd-network-hosts);
        in concatLists recs;
      };
    };
  };
}
