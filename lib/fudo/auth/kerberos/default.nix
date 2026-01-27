{ config, lib, pkgs, ... }:

with lib;
let
  realm = config.fudo.auth.kerberos.realm;
  cfg = config.fudo.auth.kerberos;

in {
  imports = [ ./kdc.nix ];

  options.fudo.auth.kerberos = {
    # Note: 'realm' option is declared in kdc.nix

    kdc-servers = mkOption {
      type = types.nullOr (types.listOf types.str);
      description =
        "Explicit KDC server addresses (disables DNS lookup for this realm)";
      default = null;
    };

    admin-server = mkOption {
      type = types.nullOr types.str;
      description = "Explicit admin server address";
      default = null;
    };

    use-dns-lookup = mkOption {
      type = types.bool;
      description = "Whether to use DNS SRV records to find KDC servers";
      default = true;
    };
  };

  config = {
    security.krb5 = {
      enable = true;
      package = pkgs.heimdal;
      settings = {
        libdefaults = {
          default_realm = realm;
          allow_weak_crypto = false;
          # Disable global DNS lookups - configure per-realm below
          dns_lookup_kdc = false;
          dns_lookup_realm = false;
          forwardable = true;
          proxiable = true;
        };
        appdefaults = {
          forwardable = true;
          proxiable = true;
          encrypt = true;
          forward = true;
        };

        # Per-realm configuration
        realms = mkIf (cfg.kdc-servers != null || cfg.admin-server != null) {
          ${realm} = mkMerge [
            (mkIf (cfg.kdc-servers != null) { kdc = cfg.kdc-servers; })
            (mkIf (cfg.admin-server != null) {
              admin_server = cfg.admin-server;
            })
            # If use-dns-lookup is true, add dns_lookup_kdc for this realm
            (mkIf cfg.use-dns-lookup { dns_lookup = "srv"; })
          ];
        };
      };
    };

    # Disable automatic PAM krb5 module - we configure it manually in nixos-config
    # to control authentication order (local password first, then Kerberos fallback)
    security.pam.krb5.enable = false;

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
