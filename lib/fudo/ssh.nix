{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.ssh;
  hostname = config.instance.hostname;

in {
  options.fudo.ssh = with types; {
    whitelistIPs = mkOption {
      type = listOf str;
      description =
        "IPs to which fail2ban rules will not apply (on top of local networks).";
      default = [];
    };
  };

  config = {
    services.fail2ban = {
      ignoreIP =
        config.instance.local-networks ++ cfg.whitelistIPs;
      maxretry = if config.fudo.hosts.${hostname}.hardened then 3
        else 20;
    };

    programs.ssh.knownHosts = let
      keyed-hosts =
        filterAttrs (h: o: o.ssh-pubkeys != [])
          config.fudo.hosts;

      crossProduct = f: list0: list1:
        concatMap (el0: map (el1: f el0 el1) list1) list0;

      all-hostnames = hostname: opts:
        [ hostname ] ++
        (crossProduct (host: domain: "${host}.${domain}")
          ([ hostname ] ++ opts.aliases)
          ([ opts.domain ] ++ opts.extra-domains));

    in mapAttrs (hostname: hostOpts: {
      publicKeyFile = builtins.head hostOpts.ssh-pubkeys;
      hostNames = all-hostnames hostname hostOpts;
    }) keyed-hosts;
  };
}
