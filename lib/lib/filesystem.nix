{ pkgs, ... }:

with pkgs.lib;
let
  head-or-null = lst: if (lst == []) then null else head lst;
  is-regular-file = filename: type: type == "regular" || type == "link";
  regular-files = path: filterAttrs is-regular-file (builtins.readDir path);
  matches-ext = ext: filename: type: (builtins.match ".+[.]${ext}$" filename) != null;
  is-nix-file = matches-ext "nix";
  strip-ext = ext: filename: head-or-null (builtins.match "(.+)[.]${ext}$" filename);
  get-ext = filename: head-or-null (builtins.match "^.+[.](.+)$" filename);
  hostname-from-file = filename: strip-ext "nix";
  nix-files = path:
    attrNames
      (filterAttrs is-nix-file
        (filterAttrs is-regular-file
          (builtins.readDir path)));

  basename-to-file-map = path: let
    files = nix-files path;
  in listToAttrs
    (map (file:
      nameValuePair (strip-ext "nix" file)
        (path + "/${file}"))
      files);

  import-by-basename = path:
    mapAttrs (attr: attr-file: import attr-file)
      (basename-to-file-map path);

  list-nix-files = nix-files;
in {
  inherit basename-to-file-map import-by-basename list-nix-files;
}
