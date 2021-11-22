{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.slynk;

  initScript = port: load-paths: let
    load-path-string =
      concatStringsSep " " (map (path: "\"${path}\"") load-paths);
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

  lisp-libs = with pkgs.lispPackages; [
    alexandria
    asdf-package-system
    asdf-system-connections
    cl_plus_ssl
    cl-ppcre
    quicklisp
    quri
    uiop
    usocket
  ];

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

      serviceConfig = let
        load-paths = (map (pkg: "${pkg}/lib/common-lisp/") lisp-libs);
      in {
        ExecStartPre = "${pkgs.lispPackages.quicklisp}/bin/quicklisp init";
        ExecStart = "${pkgs.sbcl}/bin/sbcl --load ${initScript cfg.port load-paths}";
        Restart = "on-failure";
        PIDFile = "/run/slynk.$USERNAME.pid";
      };

      path = with pkgs; [
        gcc
        glibc # for getent
        file
      ];

      environment = {
        LD_LIBRARY_PATH = "${pkgs.openssl_1_1.out}/lib";
      };
    };
  };
}
