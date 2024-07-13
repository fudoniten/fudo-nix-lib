{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.slynk;

  initScript = port: load-paths:
    let
      load-path-string =
        concatStringsSep " " (map (path: ''"${path}"'') load-paths);
    in pkgs.writeText "slynk.lisp" ''
      (load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
      (ql:quickload :slynk)
      (setf asdf:*central-registry*
       (append asdf:*central-registry*
        (list ${load-path-string})))
      (slynk:create-server :port ${toString port} :dont-close t)
      (dolist (var '("LD_LIBRARY_PATH"))
        (format t "~S: ~S~%" var (sb-unix::posix-getenv var)))

      (loop (sleep 60))
    '';

  sbclWithLibs = pkgs.sbcl.withPackages (ps:
    with ps; [
      alexandria
      asdf-package-system
      asdf-system-connections
      cl_plus_ssl
      cl-ppcre
      quicklisp
      quri
      uiop
      usocket
    ]);

in {
  options.fudo.slynk = {
    enable = mkEnableOption "Enable Slynk emacs common lisp server.";

    port = mkOption {
      type = types.int;
      description = "Port on which to open a Slynk server.";
      default = 4005;
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services.slynk = {
      description = "Slynk Common Lisp server.";

      serviceConfig = {
        ExecStart = "sbcl --load ${initScript cfg.port load-paths}";
        Restart = "on-failure";
        PIDFile = "/run/slynk.$USERNAME.pid";
      };

      path = with pkgs; [
        gcc
        glibc # for getent
        file
        sbclWithLibs
      ];

      environment = { LD_LIBRARY_PATH = "${pkgs.openssl.out}/lib"; };
    };
  };
}
