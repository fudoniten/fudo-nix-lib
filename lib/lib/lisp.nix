{ pkgs, ... }:

with pkgs.lib;
rec {
  gather-dependencies = pkg: unique (pkg.propagatedBuildInputs ++ (concatMap gather-dependencies pkg.propagatedBuildInputs));
  
  lisp-source-registry = pkg: concatStringsSep ":" (map (p: "${p}//") (gather-dependencies pkg));
}
