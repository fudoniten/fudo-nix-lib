{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.fudo.mail-server;

  createDomainDkimCert = dom:
    let
      dkim_key = "${cfg.dkim.key-directory}/${dom}.${cfg.dkim.selector}.key";
      dkim_txt = "${cfg.dkim.key-directory}/${dom}.${cfg.dkim.selector}.txt";
    in ''
      if [ ! -f "${dkim_key}" ] || [ ! -f "${dkim_txt}" ]; then
        ${cfg.dkim.package}/bin/opendkim-genkey -s "${cfg.dkim.selector}" \
          -d "${dom}" \
          --bits="${toString cfg.dkim.key-bits}" \
          --directory="${cfg.dkim.key-directory}"
        mv "${cfg.dkim.key-directory}/${cfg.dkim.selector}.private" "${dkim_key}"
        mv "${cfg.dkim.key-directory}/${cfg.dkim.selector}.txt" "${dkim_txt}"
        echo "Generated key for domain ${dom} selector ${cfg.dkim.selector}"
      fi
    '';

  createAllCerts =
    lib.concatStringsSep "\n" (map createDomainDkimCert cfg.local-domains);

  keyTable = pkgs.writeText "opendkim-KeyTable" (lib.concatStringsSep "\n"
    (lib.flip map cfg.local-domains (dom:
      "${dom} ${dom}:${cfg.dkim.selector}:${cfg.dkim.key-directory}/${dom}.${cfg.dkim.selector}.key")));
  signingTable = pkgs.writeText "opendkim-SigningTable"
    (lib.concatStringsSep "\n"
      (lib.flip map cfg.local-domains (dom: "${dom} ${dom}")));

  dkim = config.services.opendkim;
  args = [ "-f" "-l" ]
    ++ lib.optionals (dkim.configFile != null) [ "-x" dkim.configFile ];
in {

  options.fudo.mail-server.dkim = {
    signing = mkOption {
      type = types.bool;
      default = true;
      description = "Enable dkim signatures for mail.";
    };

    key-directory = mkOption {
      type = types.str;
      default = "/var/dkim";
      description = "Path to use to store DKIM keys.";
    };

    selector = mkOption {
      type = types.str;
      default = "mail";
      description = "Name to use for mail-signing keys.";
    };

    key-bits = mkOption {
      type = types.int;
      default = 2048;
      description = ''
        How many bits in generated DKIM keys. RFC6376 advises minimum 1024-bit keys.

        If you have already deployed a key with a different number of bits than specified
        here, then you should use a different selector (dkimSelector). In order to get
        this package to generate a key with the new number of bits, you will either have to
        change the selector or delete the old key file.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.opendkim;
      description = "OpenDKIM package to use.";
    };
  };

  config = mkIf (cfg.dkim.signing && cfg.enable) {
    services.opendkim = {
      enable = true;
      selector = cfg.dkim.selector;
      domains = "csl:${builtins.concatStringsSep "," cfg.local-domains}";
      configFile = pkgs.writeText "opendkim.conf" (''
        Canonicalization relaxed/simple
        UMask 0002
        Socket ${dkim.socket}
        KeyTable file:${keyTable}
        SigningTable file:${signingTable}
      '' + (lib.optionalString cfg.debug ''
        Syslog yes
        SyslogSuccess yes
        LogWhy yes
      ''));
    };

    users.users = {
      "${config.services.postfix.user}" = {
        extraGroups = [ "${config.services.opendkim.group}" ];
      };
    };

    systemd = {
      tmpfiles.rules = [
        "d '${cfg.dkim.key-directory}' - ${config.services.opendkim.user} ${config.services.opendkim.group} - -"
      ];
      services.opendkim = {
        preStart = lib.mkForce createAllCerts;
        serviceConfig = {
          ExecStart = lib.mkForce
            "${cfg.dkim.package}/bin/opendkim ${escapeShellArgs args}";
          PermissionsStartOnly = lib.mkForce false;
          ReadWritePaths = [ cfg.dkim.key-directory ];
        };
      };
    };
  };
}
