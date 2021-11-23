{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.informis.cl-gemini;

  feedOpts = { ... }: with types; {
    options = {
      url = mkOption {
        type = str;
        description = "Base URI of the feed, i.e. the URI corresponding to the feed path.";
        example = "gemini://my.server/path/to/feedfiles";
      };

      title = mkOption {
        type = str;
        description = "Title of given feed.";
        example = "My Fancy Feed";
      };

      path = mkOption {
        type = str;
        description = "Path to Gemini files making up the feed.";
        example = "/path/to/feed";
      };
    };
  };

  ensure-certificates = hostname: user: key: cert: pkgs.writeShellScript "ensure-gemini-certificates.sh" ''
    if [[ ! -e ${key} ]]; then
      TARGET_CERT_DIR=$(${pkgs.coreutils}/bin/dirname ${cert})
      TARGET_KEY_DIR=$(${pkgs.coreutils}/bin/dirname ${key})
      if [[ ! -d $TARGET_CERT_DIR ]]; then mkdir -p $TARGET_CERT_DIR; fi
      if [[ ! -d $TARGET_KEY_DIR ]]; then mkdir -p $TARGET_KEY_DIR; fi
      ${pkgs.openssl}/bin/openssl req -new -subj "/CN=.${hostname}" -addext "subjectAltName = DNS:${hostname}, DNS:.${hostname}" -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 3650 -nodes -out ${cert} -keyout ${key}
      ${pkgs.coreutils}/bin/chown -R ${user}:nogroup ${cert}
      ${pkgs.coreutils}/bin/chown -R ${user}:nogroup ${key}
      ${pkgs.coreutils}/bin/chmod 0444 ${cert}
      ${pkgs.coreutils}/bin/chmod 0400 ${key}
    fi
  '';

  generate-feeds = feeds:
    let
      feed-strings = mapAttrsToList (feed-name: opts:
        "(cl-gemini:register-feed :name \"${feed-name}\" :title \"${opts.title}\" :path \"${opts.path}\" :base-uri \"${opts.url}\")") feeds;
    in pkgs.writeText "gemini-local-feeds.lisp" (concatStringsSep "\n" feed-strings);

in {
  options.informis.cl-gemini = with types; {
    enable = mkEnableOption "Enable the cl-gemini server.";

    port = mkOption {
      type = port;
      description = "Port on which to serve Gemini traffic.";
      default = 1965;
    };

    hostname = mkOption {
      type = str;
      description = "Hostname at which the server is available (for generating the SSL certificate).";
      example = "my.hostname.com";
    };

    user = mkOption {
      type = str;
      description = "User as which to run the cl-gemini server.";
      default = "cl-gemini";
    };

    server-ip = mkOption {
      type = str;
      description = "IP on which to serve Gemini traffic.";
      example = "1.2.3.4";
    };

    document-root = mkOption {
      type = str;
      description = "Root at which to look for gemini files.";
      example = "/my/gemini/root";
    };

    user-public = mkOption {
      type = str;
      description = "Subdirectory of user homes to check for gemini files.";
      default = "gemini-public";
    };

    ssl-private-key = mkOption {
      type = str;
      description = "Path to the pem-encoded server private key.";
      example = "/path/to/secret/key.pem";
      default = "${config.users.users.cl-gemini.home}/private/server-key.pem";
    };

    ssl-certificate = mkOption {
      type = str;
      description = "Path to the pem-encoded server public certificate.";
      example = "/path/to/cert.pem";
      default = "${config.users.users.cl-gemini.home}/private/server-cert.pem";
    };

    slynk-port = mkOption {
      type = nullOr port;
      description = "Port on which to open a slynk server, if any.";
      default = null;
    };

    feeds = mkOption {
      type = attrsOf (submodule feedOpts);
      description = "Feeds to generate and make available (as eg. /feed/name.xml).";
      example = {
        diary = {
          title = "My Diary";
          path = "/path/to/my/gemfiles/";
          url = "gemini://my.host/blog-path/";
        };
      };
      default = {};
    };

    textfiles-archive = mkOption {
      type = str;
      description = "A path containing only gemini & text files.";
      example = "/path/to/textfiles/";
    };
  };

  config = mkIf cfg.enable {

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    users.users = {
      ${cfg.user} = {
        isSystemUser = true;
        group = "nogroup";
        createHome = true;
        home = "/var/lib/${cfg.user}";
      };
    };

    systemd.services = {
      cl-gemini = {
        description = "cl-gemini Gemini server (https://gemini.circumlunar.space/)";

        serviceConfig = {
          ExecStartPre = "${ensure-certificates cfg.hostname cfg.user cfg.ssl-private-key cfg.ssl-certificate}";
          ExecStart = "${pkgs.cl-gemini}/bin/launch-server.sh";
          Restart = "on-failure";
          PIDFile = "/run/cl-gemini.$USERNAME.uid";
          User = cfg.user;
        };

        environment = {
          GEMINI_SLYNK_PORT = mkIf (cfg.slynk-port != null) (toString cfg.slynk-port);
          GEMINI_LISTEN_IP = cfg.server-ip;
          GEMINI_PRIVATE_KEY = cfg.ssl-private-key;
          GEMINI_CERTIFICATE = cfg.ssl-certificate;
          GEMINI_LISTEN_PORT = toString cfg.port;
          GEMINI_DOCUMENT_ROOT = cfg.document-root;
          GEMINI_TEXTFILES_ROOT = cfg.textfiles-archive;
          GEMINI_FEEDS = "${generate-feeds cfg.feeds}";

          CL_SOURCE_REGISTRY = "${lib.lisp.lisp-source-registry pkgs.cl-gemini}";
        };

        path = with pkgs; [
          gcc
          file
          getent
        ];

        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
