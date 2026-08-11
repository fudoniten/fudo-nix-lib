{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.secrets;

  encrypt-on-disk = { secret-name, target-host, target-pubkey, source-file }:
    pkgs.stdenv.mkDerivation {
      name = "${target-host}-${secret-name}-secret";
      phases = "installPhase";
      buildInputs = [ pkgs.age ];
      installPhase = ''
        age -a -r "${target-pubkey}" -o $out ${source-file}
      '';
    };

  # The secret is installed by renaming a fully written file over the target,
  # never by writing the target in place.  Writing in place -- `rm -f`,
  # `touch`, then decrypt onto the target -- leaves a window on every restart
  # in which the target is first absent and then zero length, and readers do
  # not know to wait: NixOS's sshd-keygen.service sampled exactly that window,
  # concluded the host key it found was missing, and raced this script to
  # generate a replacement over a key that was about to land.  A rename within
  # one filesystem is atomic, so a reader sees the old contents or the new
  # ones and nothing in between.
  #
  # Failing without touching the target matters as much: a decrypt that dies
  # half way now leaves the previous secret in place and fails the unit, where
  # before it left an empty file behind and called that success.
  decrypt-script = { secret-name, source-file, target-host, target-file
    , host-master-key, user, group, permissions }:
    let
      encrypted-file = encrypt-on-disk {
        inherit secret-name source-file target-host;
        target-pubkey = host-master-key.public-key;
      };
    in pkgs.writeShellScript
    "decrypt-fudo-secret-${target-host}-${secret-name}.sh" ''
      set -euo pipefail

      # Armed before either file exists, so that a mktemp that fails part way
      # through still cleans up after the one that succeeded.  `rm -f ""` is a
      # no-op, and under `set -u` both names have to be defined for the trap
      # to run at all.
      SRC=""
      TMP=""
      trap 'rm -f "$SRC" "$TMP"' EXIT

      # NOTE: silly hack because sometimes age leaves a blank line
      # Only include lines with at least one non-space character
      SRC=$(mktemp -p /run fudo-secret-${target-host}-${secret-name}.XXXXXXXX)

      # Staged beside the target so the install below is a rename within a
      # single filesystem.  mktemp creates it 0600, so the plaintext is never
      # readable by anyone but root, even briefly.
      TMP=$(mktemp "${dirOf target-file}/.${secret-name}.XXXXXXXX")

      grep "[^ ]" "${encrypted-file}" > "$SRC"

      # Decrypt to stdout rather than with `-o`: the staging file already
      # exists, and this way its permissions are the ones mktemp chose.
      age -d -i ${host-master-key.key-path} "$SRC" > "$TMP"

      chown ${user}:${group} "$TMP"
      chmod ${permissions} "$TMP"
      mv -f "$TMP" "${target-file}"
    '';

  secret-service = target-host: secret-name:
    { source-file, target-file, user, group, permissions, ... }: {
      description =
        "decrypt secret ${secret-name} at ${target-host}:${target-file}.";
      wantedBy = [ "multi-user.target" ];
      requiredBy = [ cfg.secret-target ];
      requires = [ "local-fs.target" ];
      before = [ cfg.secret-target ];
      after = [ "local-fs.target" ];
      restartIfChanged = true;
      # A changed unit is restarted in one step rather than stopped in the old
      # configuration and started in the new one, so the secret is replaced by
      # the single rename in the decrypt script instead of disappearing for
      # the length of an activation.
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre =
          pkgs.writeShellScript "fudo-secret-prep-${secret-name}.sh" ''
            if [ ! -d ${dirOf target-file} ]; then
              mkdir -p ${dirOf target-file}
              chown ${user}:${group} ${dirOf target-file}
              chmod ${if (group == null) then "0550" else "0500"} ${
                dirOf target-file
              }
            fi
          '';
        ExecStart =
          let host-master-key = config.fudo.hosts."${target-host}".master-key;
          in decrypt-script {
            inherit secret-name source-file target-host target-file
              host-master-key user group permissions;
          };
        # No ExecStop removing the target.  It deleted the live secret on the
        # way through every restart, and if the new configuration then failed
        # to start, nothing put it back -- so a bad deploy took the secret
        # with it rather than leaving the working one in place.  The decrypt
        # script replaces the file atomically, which is what the removal was
        # standing in for.
      };
      path = [ pkgs.age ];
    };

  secretOpts = { name, ... }: {
    options = with types; {
      source-file = mkOption {
        type =
          path; # CAREFUL: this will copy the file to nixstore...keep on deploy host
        description =
          "File from which to load the secret. If unspecified, a random new password will be generated.";
        default = "${generate-secret name}/passwd";
      };

      target-file = mkOption {
        type = str;
        description =
          "Target file on the host; the secret will be decrypted to this file.";
      };

      user = mkOption {
        type = str;
        description = "User (on target host) to which the file will belong.";
        default = "root";
      };

      group = mkOption {
        type = str;
        description = "Group (on target host) to which the file will belong.";
        default = "root";
      };

      permissions = mkOption {
        type = str;
        description = "Permissions to set on the target file.";
        default = "0400";
      };

      metadata = mkOption {
        type = attrsOf anything;
        description = "Arbitrary metadata associated with this secret.";
        default = { };
      };

      service = mkOption {
        type = str;
        description = "Host-side name of the service decrypting this secret.";
        default = "fudo-secret-${name}.service";
      };
    };
  };

  nix-build-users = let usernames = attrNames config.users.users;
  in filter (user: (builtins.match "^nixbld[0-9]{1,2}$" user) != null)
  usernames;

  generate-secret = name:
    pkgs.stdenv.mkDerivation {
      name = "${name}-generated-passwd";

      phases = [ "buildPhase" "installPhase" ];

      buildInputs = with pkgs; [ pwgen ];

      buildPhase = ''
        echo "${name}-${config.instance.build-timestamp}" >> file.txt
        pwgen --secure --symbols --num-passwords=1 --sha1=file.txt 40 > passwd
        rm -f file.txt
      '';

      installPhase = ''
        mkdir $out
        mv passwd $out/passwd
      '';
    };

in {
  options.fudo.secrets = with types; {
    enable = mkOption {
      type = bool;
      description =
        "Include secrets in the build (disable when secrets are unavailable)";
      default = true;
    };

    host-secrets = mkOption {
      type = attrsOf (attrsOf (submodule secretOpts));
      description = "Map of hosts to host secrets";
      default = { };
    };

    host-deep-secrets = mkOption {
      type = attrsOf (attrsOf (submodule secretOpts));
      description = ''
        Secrets that are only passed during deployment.

        These secrets will be passed as nixops deployment secrets,
        _unlike_ regular secrets that are passed to hosts as part of
        the nixops store, but encrypted with the host SSH key. Regular
        secrets are kept secret from normal users. These secrets will
        be kept secret from _everybody_. However, they won't be
        available on the host at boot until a new deployment occurs.
      '';
      default = { };
    };

    secret-users = mkOption {
      type = listOf str;
      description = "List of users with read-access to secrets.";
      default = [ ];
    };

    secret-group = mkOption {
      type = str;
      description = "Group to which secrets will belong.";
      default = "nixops-secrets";
    };

    secret-paths = mkOption {
      type = listOf str;
      description =
        "Paths which contain (only) secrets. The contents will be reabable by the secret-group.";
      default = [ ];
    };

    secret-target = mkOption {
      type = str;
      description = "Target indicating that all secrets are available.";
      default = "fudo-secrets.target";
    };
  };

  config = mkIf cfg.enable {
    users.groups = {
      ${cfg.secret-group} = { members = cfg.secret-users ++ nix-build-users; };
    };

    systemd = let
      hostname = config.instance.hostname;

      host-secrets = if (hasAttr hostname cfg.host-secrets) then
        cfg.host-secrets.${hostname}
      else
        { };

      host-secret-services = let
        head-or-null = lst: if (lst == [ ]) then null else head lst;
        strip-service = service-name:
          head-or-null (builtins.match "^(.+)[.]service$" service-name);
      in mapAttrs' (secret: secretOpts:
        (nameValuePair (strip-service secretOpts.service)
          (secret-service hostname secret secretOpts))) host-secrets;

      trace-all = obj: builtins.trace obj obj;

      host-secret-paths = mapAttrsToList (secret: secretOpts:
        let perms = if secretOpts.group != "nobody" then "550" else "500";
        in "d ${
          dirOf secretOpts.target-file
        } ${perms} ${secretOpts.user} ${secretOpts.group} - -") host-secrets;

      build-secret-paths =
        map (path: "d '${path}' - root ${cfg.secret-group} - -")
        cfg.secret-paths;

    in {
      tmpfiles.rules = unique (host-secret-paths ++ build-secret-paths);

      services = host-secret-services // {
        fudo-secrets-watcher = mkIf (length cfg.secret-paths > 0) {
          wantedBy = [ "multi-user.target" ];
          description =
            "Ensure access for group ${cfg.secret-group} to fudo secret paths.";
          serviceConfig = {
            ExecStart = pkgs.writeShellScript "fudo-secrets-watcher.sh"
              (concatStringsSep "\n" (map (path: ''
                chown -R root:${cfg.secret-group} ${path}
                chmod -R u=rwX,g=rX,o= ${path}
              '') cfg.secret-paths));
          };
        };
      };

      targets = let
        strip-ext = filename: head (builtins.match "^(.+)[.]target$" filename);
      in {
        ${strip-ext cfg.secret-target} = {
          description =
            "Target indicating that all Fudo secrets are available.";
          wantedBy = [ "multi-user.target" ];
        };
      };

      paths.fudo-secrets-watcher = mkIf (length cfg.secret-paths > 0) {
        wantedBy = [ "multi-user.target" ];
        description = "Watch fudo secret paths, and correct perms on changes.";
        pathConfig = {
          PathChanged = cfg.secret-paths;
          Unit = "fudo-secrets-watcher.service";
        };
      };
    };
  };
}
