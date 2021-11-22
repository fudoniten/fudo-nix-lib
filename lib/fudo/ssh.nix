{ config, lib, pkgs, ... }:

with lib;
{
  config = {
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
