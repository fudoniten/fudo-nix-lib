{ pkgs, ... }:

with pkgs.lib;
let
  generate-mac-address = hostname: interface: pkgs.stdenv.mkDerivation {
    name = "mk-mac-${hostname}-${interface}";
    phases = [ "installPhase" ];
    installPhase = ''
      echo ${hostname}-${interface} | sha1sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/' > $out
    '';
  };

  # dropUntil = pred: lst: let
  #   drop-until-helper = pred: lst:
  #     if (length lst) == 0 then [] else
  #       if (pred (head lst)) then lst else (drop-until-helper pred (tail lst));
  # in drop-until-helper pred lst;

  # dropWhile = pred: dropUntil (el: !(pred el));

  # is-whitespace = str: (builtins.match "^[[:space:]]*$" str) != null;

  # stripWhitespace = str: let
  #   lines = builtins.split "\n" str;
  #   lines-front-stripped = dropWhile is-whitespace lines;
  #   lines-rear-stripped = lib.reverseList
  #     (dropWhile is-whitespace
  #       (lib.reverseList lines-front-stripped));
  # in concatStringsSep "\n" lines-rear-stripped;

  host-ipv4 = config: hostname: let
    domain = config.fudo.hosts.${hostname}.domain;
    host-network = config.fudo.zones.${domain};
  in host-network.hosts.${hostname}.ipv4-address;

  host-ipv6 = config: hostname: let
    domain = config.fudo.hosts.${hostname}.domain;
    host-network = config.fudo.zones.${domain};
  in host-network.hosts.${hostname}.ipv6-address;

  host-ips = config: hostname: let
    ipv4 = host-ipv4 config hostname;
    ipv6 = host-ipv6 config hostname;
    not-null = o: o != null;
  in filter not-null [ ipv4 ipv6 ];

  site-gateway = config: site-name: let
    site = config.fudo.sites.${site-name};
  in if (site.local-gateway != null)
     then host-ipv4 config site.local-gateway
     else site.gateway-v4;

in {
  inherit host-ipv4 host-ipv6 host-ips site-gateway;

  generate-mac-address = hostname: interface: let
    pkg = generate-mac-address hostname interface;
  in removeSuffix "\n" (builtins.readFile "${pkg}");
}
