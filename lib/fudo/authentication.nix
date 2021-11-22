{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.authentication;
in {
  options.fudo.authentication = {
    enable = mkEnableOption "Use Fudo users & groups from LDAP.";

    ssl-ca-certificate = mkOption {
      type = types.str;
      description = "Path to the CA certificate to use to bind to the server.";
    };

    bind-passwd-file = mkOption {
      type = types.str;
      description = "Path to a file containing the password used to bind to the server.";
    };

    ldap-url = mkOption {
      type = types.str;
      description = "URL of the LDAP server.";
      example = "ldaps://auth.fudo.org";
    };

    base = mkOption {
      type = types.str;
      description = "The LDAP base in which to look for users.";
      default = "dc=fudo,dc=org";
    };

    bind-dn = mkOption {
      type = types.str;
      description = "The DN with which to bind the LDAP server.";
      default = "cn=auth_reader,dc=fudo,dc=org";
    };
  };

  config = mkIf cfg.enable {
    users.ldap = {
      enable = true;
      base = cfg.base;
      bind = {
        distinguishedName = cfg.bind-dn;
        passwordFile = cfg.bind-passwd-file;
        timeLimit = 5;
      };
      loginPam = true;
      nsswitch = true;
      server = cfg.ldap-url;
      timeLimit = 5;
      useTLS = true;
      extraConfig = ''
        TLS_CACERT ${cfg.ssl-ca-certificate}
        TSL_REQCERT allow
      '';

      daemon = {
        enable = true;
        extraConfig = ''
          tls_cacertfile ${cfg.ssl-ca-certificate}
          tls_reqcert allow
        '';
      };
    };
  };
}
