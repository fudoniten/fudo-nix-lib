{ pkgs, ... }:

with pkgs.lib;
let
  hash-ldap-passwd-pkg = name: passwd-file: pkgs.stdenv.mkDerivation {
    name = "${name}-ldap-passwd";

    phases = [ "installPhase" ];

    buildInputs = with pkgs; [ openldap ];

    installPhase = let
      passwd = removeSuffix "\n" (readFile passwd-file);
    in ''
      slappasswd -s ${passwd} > $out
    '';
  };

  hash-ldap-passwd = name: passwd-file:
    builtins.readFile "${hash-ldap-passwd-pkg name passwd-file}";

  generate-random-passwd = name: length: pkgs.stdenv.mkDerivation {
    name = "${name}-random-passwd";

    phases = [ "installPhase" ];

    buildInputs = with pkgs; [ pwgen ];

    installPhase = ''
      pwgen --secure --num-passwords=1 ${toString length} > $out
    '';
  };

  generate-stablerandom-passwd = name: { seed, length ? 20, ... }:
    pkgs.stdenv.mkDerivation {
      name = "${name}-stablerandom-passwd";

      phases = [ "installPhase" ];

      buildInputs = with pkgs; [ pwgen ];

      installPhase = ''
        echo "${name}-${seed}" > seedfile
        pwgen --secure --num-passwords=1 -H seedfile ${toString length} > $out
      '';
    };

in {
  hash-ldap-passwd = hash-ldap-passwd;

  random-passwd-file = name: length:
    builtins.toPath "${generate-random-passwd name length}";

  stablerandom-passwd-file = name: seed:
    builtins.toPath "${generate-stablerandom-passwd name { seed = seed; }}";
}
