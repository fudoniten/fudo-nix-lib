{ pkgs, ... }:

with pkgs.lib;
let
  get-basename-without-hash = filename:
    head (builtins.match "^[a-zA-Z0-9]+-(.+)$" (baseNameOf filename));

  format-json-file = filename: pkgs.stdenv.mkDerivation {
    name = "formatted-${get-basename-without-hash filename}";
    phases = [ "installPhase" ];
    buildInputs = with pkgs; [ python ];
    installPhase = "python -mjson.tool ${filename} > $out";
  };

in {
  inherit format-json-file;
}
