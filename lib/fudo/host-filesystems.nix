{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;
  host-filesystems = config.fudo.hosts.${hostname}.encrypted-filesystems;

  optionalOrDefault = str: default: if (str != null) then str else default;

  filesystemsToMountpointLists =
    mapAttrsToList (fs: fsOpts: fsOpts.mountpoints);

  concatMapAttrs = f: as: concatMap (i: i) (mapAttrsToList f as);

  concatMapAttrsToList = f: attrs: concatMap (i: i) (mapAttrsToList f attrs);

in {
  config = {
    users.groups = let
      site-name = config.instance.local-site;
      site-hosts = filterAttrs (hostname: hostOpts: hostOpts.site == site-name)
        config.fudo.hosts;
      site-mountpoints = concatMapAttrsToList (host: hostOpts:
        concatMapAttrsToList (fs: fsOpts: attrValues fsOpts.mountpoints)
        hostOpts.encrypted-filesystems) site-hosts;
    in listToAttrs
    (map (mp: nameValuePair mp.group { members = mp.users; }) site-mountpoints);

    systemd = {
      # Ensure the mountpoints exist
      tmpfiles.rules = let
        mpPerms = mpOpts: if mpOpts.world-readable then "755" else "750";
        mountpointToPath = mp: mpOpts:
          "d '${mp}' ${mpPerms mpOpts} root ${
            optionalOrDefault mpOpts.group "-"
          } - -";
        filesystemsToMountpointLists =
          mapAttrsToList (fs: fsOpts: fsOpts.mountpoints);
        mountpointListsToPaths =
          concatMap (mps: mapAttrsToList mountpointToPath mps);
      in mountpointListsToPaths (filesystemsToMountpointLists host-filesystems);

      # Actual mounts of decrypted filesystems
      mounts = let
        filesystems = mapAttrsToList (fs: opts: {
          filesystem = fs;
          opts = opts;
        }) host-filesystems;

        mounts = concatMap (fs:
          mapAttrsToList (mp: mp-opts: {
            what = "/dev/mapper/${fs.filesystem}";
            type = fs.opts.filesystem-type;
            where = mp;
            options = concatStringsSep "," (fs.opts.options ++ mp-opts.options);
            description =
              "${fs.opts.filesystem-type} filesystem on ${fs.filesystem} mounted to ${mp}";
            requires = [ "${fs.filesystem}-decrypt.service" ];
            partOf = [ "${fs.filesystem}.target" ];
            wantedBy = [ "${fs.filesystem}.target" ];
          }) fs.opts.mountpoints) filesystems;
      in mounts;

      # Jobs to decrypt the encrypted devices
      services = mapAttrs' (filesystem-name: opts:
        nameValuePair "${filesystem-name}-decrypt" {
          description =
            "Decrypt the ${filesystem-name} filesystem when the key is available at ${opts.key-path}";
          path = with pkgs; [ cryptsetup ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "decrypt-${filesystem-name}.sh" ''
              [ -e /dev/mapper/${filesystem-name} ] || cryptsetup open --type ${opts.type} --key-file ${opts.key-path} ${opts.encrypted-device} ${filesystem-name}
            '';
            ExecStartPost = mkIf opts.remove-key
              (pkgs.writeShellScript "remove-${filesystem-name}-key.sh" ''
                rm ${opts.key-path}
              '');
            ExecStop = pkgs.writeShellScript "close-${filesystem-name}.sh" ''
              cryptsetup close /dev/mapper/${filesystem-name}
            '';
          };
          restartIfChanged = true;
        }) host-filesystems;

      # Watch the path of the key, trigger decrypt when it's available
      paths = let
        decryption-jobs = mapAttrs' (filesystem-name: opts:
          nameValuePair "${filesystem-name}-decrypt" {
            wantedBy = [ "default.target" ];
            description =
              "Watch for decryption key, then decrypt the target filesystem.";
            pathConfig = {
              PathExists = opts.key-path;
              Unit = "${filesystem-name}-decrypt.service";
            };
          }) host-filesystems;

        post-decryption-jobs = mapAttrs' (filesystem-name: opts:
          nameValuePair "${filesystem-name}-mount" {
            wantedBy = [ "default.target" ];
            description =
              "Mount ${filesystem-name} filesystems once the decrypted device is available.";
            pathConfig = {
              PathExists = "/dev/mapper/${filesystem-name}";
              Unit = "${filesystem-name}.target";
            };
          }) host-filesystems;
      in decryption-jobs // post-decryption-jobs;

      targets = mapAttrs (filesystem-name: opts: {
        description = "${filesystem-name} enabled and available.";
      }) host-filesystems;
    };
  };
}
