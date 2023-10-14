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

  decrypt-script = { secret-name, source-file, target-host, target-file
    , host-master-key, user, group, permissions }:
    pkgs.writeShellScript
    "decrypt-fudo-secret-${target-host}-${secret-name}.sh" ''
      rm -f ${target-file}
      touch ${target-file}
      chown ${user}:${group} ${target-file}
      chmod ${permissions} ${target-file}
      # NOTE: silly hack because sometimes age leaves a blank line
      # Only include lines with at least one non-space character
      SRC=$(mktemp fudo-secret-${target-host}-${secret-name}.XXXXXXXX)
      cat ${
        encrypt-on-disk {
          inherit secret-name source-file target-host;
          target-pubkey = host-master-key.public-key;
        }
      } | grep "[^ ]" > $SRC
      age -d -i ${host-master-key.key-path} -o ${target-file} $SRC
      rm -f $SRC
    '';

  secret-service = target-host: secret-name:
    { source-file, target-file, user, group, permissions, ... }: {
      description =
        "decrypt secret ${secret-name} at ${target-host}:${target-file}.";
      wantedBy = [ "default.target" cfg.secret-target ];
      requires = [ "local-fs.target" ];
      before = [ cfg.secret-target ];
      after = [ "local-fs.target" ];
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
        ExecStop = pkgs.writeShellScript "fudo-remove-${secret-name}-secret.sh"
          "rm -f ${target-file}";
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

      phases = [ "installPhase" ];

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
