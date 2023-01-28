{ config, lib, pkgs, ... }:

let realm = config.fudo.auth.kerberos.realm;

in {
  imports = [ ./kdc.nix ];

  config = {
    krb5 = {
      enable = true;
      kerberos = pkgs.heimdal;
      libdefaults = {
        default_realm = realm;
        allow_weak_crypto = false;
        dns_lookup_kdc = true;
        dns_lookup_realm = true;
        forwardable = true;
        proxiable = true;
      };
      appdefaults = {
        forwardable = true;
        proxiable = true;
        encrypt = true;
        forward = true;
      };
    };

    security.pam.krb5.enable = true;

    services.openssh = {
      extraConfig = ''
        GSSAPIAuthentication yes
        GSSAPICleanupCredentials yes
      '';
    };

    programs.ssh = {
      extraConfig = ''
        GSSAPIAuthentication yes
        GSSAPIDelegateCredentials yes
      '';
    };
  };
}
