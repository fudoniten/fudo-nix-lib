{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.password;

  genOpts = {
    options = {
      file = mkOption {
        type = types.str;
        description = "Password file in which to store a generated password.";
      };

      user = mkOption {
        type = types.str;
        description = "User to which the file should belong.";
      };

      group = mkOption {
        type = with types; nullOr str;
        description = "Group to which the file should belong.";
        default = "nogroup";
      };

      restart-services = mkOption {
        type = with types; listOf str;
        description = "List of services to restart when the password file is generated.";
        default = [];
      };
    };
  };

  generate-passwd-file = file: user: group: pkgs.writeShellScriptBin "generate-passwd-file.sh" ''
    mkdir -p $(dirname ${file})

    if touch ${file}; then
      chown ${user}${optionalString (group != null) ":${group}"} ${file} 
      if [ $? -ne 0 ]; then
         rm ${file}
         echo "failed to set permissions on ${file}"
         exit 4
      fi
      ${pkgs.pwgen}/bin/pwgen 30 1 > ${file}
    else
      echo "cannot write to ${file}"
      exit 2
    fi

    if [ ! -f ${file} ]; then
      echo "Failed to create file ${file}"
      exit 3
    fi

    ${if (group != null) then
        "chmod 640 ${file}"
      else
        "chmod 600 ${file}"}

    echo "created password file ${file}"
    exit 0
  '';

  restart-script = service-name: ''
    SYSCTL=${pkgs.systemd}/bin/systemctl
    JOBTYPE=$(${pkgs.systemd}/bin/systemctl show ${service-name} -p Type)
    if $SYSCTL is-active --quiet ${service-name} ||
       [ $JOBTYPE == "Type=simple" ] ||
       [ $JOBTYPE == "Type=oneshot" ] ; then
      echo "restarting service ${service-name} because password has changed."
      $SYSCTL restart ${service-name}
    fi
  '';

  filterForRestarts = filterAttrs (name: opts: opts.restart-services != []);

in {
  options.fudo.password = {
    file-generator = mkOption {
      type = with types; attrsOf (submodule genOpts);
      description = "List of password files to generate.";
      default = {};
    };
  };

  config = {
    systemd.targets.fudo-passwords = {
      description = "Target indicating that all Fudo passwords have been generated.";
      wantedBy = [ "default.target" ];
    };

    systemd.services = fold (a: b: a // b) {} (mapAttrsToList (name: opts: {
      "file-generator-${name}" = {
        enable = true;
        partOf = [ "fudo-passwords.target" ];
        serviceConfig.Type = "oneshot";
        description = "Generate password file for ${name}.";
        script = "${generate-passwd-file opts.file opts.user opts.group}/bin/generate-passwd-file.sh";
        reloadIfChanged = true;
      };

      "file-generator-watcher-${name}" = mkIf (! (opts.restart-services == [])) {
        description = "Restart services upon regenerating password for ${name}";
        after = [ "file-generator-${name}.service" ];
        partOf = [ "fudo-passwords.target" ];
        serviceConfig.Type = "oneshot";
        script = concatStringsSep "\n" (map restart-script opts.restart-services);
      };
    }) cfg.file-generator);

    systemd.paths = mapAttrs' (name: opts:
      nameValuePair "file-generator-watcher-${name}" {
        partOf = [ "fudo-passwords.target"];
        pathConfig.PathChanged = opts.file;
      }) (filterForRestarts cfg.file-generator);
  };
}
