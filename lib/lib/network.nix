{ ... }:

{
  # A stable, locally-administered MAC derived from the host and interface
  # names. Hashes "<hostname>-<interface>\n" -- the trailing newline keeps the
  # result identical to the original `echo ... | sha1sum` implementation, so
  # existing hosts keep their addresses -- and formats the first five bytes
  # behind a 02: prefix (locally administered, unicast).
  generate-mac-address = hostname: interface:
    let
      hash = builtins.hashString "sha1" "${hostname}-${interface}\n";
      byte = n: builtins.substring (n * 2) 2 hash;
    in builtins.concatStringsSep ":" ([ "02" ] ++ map byte [ 0 1 2 3 4 ]);
}
