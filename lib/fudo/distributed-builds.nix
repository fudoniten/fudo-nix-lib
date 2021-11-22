{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;

  site-cfg = config.fudo.sites.${config.instance.local-site};

  has-build-servers = (length (attrNames site-cfg.build-servers)) > 0;

  build-keypair = config.fudo.secrets.host-secrets.${hostname}.build-keypair;

  enable-distributed-builds =
    site-cfg.enable-distributed-builds && has-build-servers && build-keypair != null;

  local-build-cfg = if (hasAttr hostname site-cfg.build-servers) then
    site-cfg.build-servers.${hostname}
      else null;

in {
  config = {
    nix = mkIf enable-distributed-builds {
      buildMachines = mapAttrsToList (hostname: buildOpts: {
        hostName = "${hostname}.${domain-name}";
        maxJobs = buildOpts.max-jobs;
        speedFactor = buildOpts.speed-factor;
        supportedFeatures = buildOpts.supportedFeatures;
        sshKey = build-keypair.private-key;
        sshUser = buildOpts.user;
      }) site-cfg.build-servers;
      distributedBuilds = true;

      trustedUsers = mkIf (local-build-cfg != null) [
        local-build-host.build-user
      ];
    };

    users.users = mkIf (local-build-cfg != null) {
      ${local-build-cfg.build-user} = {
        isSystemUser = true;
        openssh.authorizedKeys.keyFiles =
          concatLists
            (mapAttrsToList (host: hostOpts: hostOpts.build-pubkeys)
              config.instance.local-hosts);
      };
    };
  };
}
