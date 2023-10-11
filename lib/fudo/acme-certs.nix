{ config, lib, pkgs, ... }@toplevel:

with lib;
let
  hostname = config.instance.hostname;

  domainOpts = { name, ... }:
    let domain = name;
    in {
      options = with types; {
        admin-email = mkOption {
          type = str;
          description = "Domain administrator email.";
          default = "admin@${domain}";
        };

        extra-domains = mkOption {
          type = listOf str;
          description = "List of domains to add to this certificate.";
          default = [ ];
        };

        local-copies = let
          localCopyOpts = { name, ... }:
            let copy = name;
            in {
              options = with types;
                let target-path = "/run/ssl-certificates/${domain}/${copy}";
                in {
                  user = mkOption {
                    type = str;
                    description = "User to which this copy belongs.";
                  };

                  group = mkOption {
                    type = nullOr str;
                    description = "Group to which this copy belongs.";
                    default = null;
                  };

                  service = mkOption {
                    type = str;
                    description = "systemd job to copy certs.";
                    default = "fudo-acme-${domain}-${copy}-certs.service";
                  };

                  certificate = mkOption {
                    type = str;
                    description = "Full path to the local copy certificate.";
                    default = "${target-path}/cert.pem";
                  };

                  full-certificate = mkOption {
                    type = str;
                    description = "Full path to the local copy certificate.";
                    default = "${target-path}/fullchain.pem";
                  };

                  chain = mkOption {
                    type = str;
                    description = "Full path to the local copy certificate.";
                    default = "${target-path}/chain.pem";
                  };

                  private-key = mkOption {
                    type = str;
                    description = "Full path to the local copy certificate.";
                    default = "${target-path}/key.pem";
                  };

                  dependent-services = mkOption {
                    type = listOf str;
                    description =
                      "List of systemd services depending on this copy.";
                    default = [ ];
                  };

                  part-of = mkOption {
                    type = listOf str;
                    description =
                      "List of systemd targets to which this copy belongs.";
                    default = [ ];
                  };
                };
            };
        in mkOption {
          type = attrsOf (submodule localCopyOpts);
          description = "Map of copies to make for use by services.";
          default = { };
        };
      };
    };

  head-or-null = lst: if (lst == [ ]) then null else head lst;
  rm-service-ext = filename:
    head-or-null (builtins.match "^(.+).service$" filename);

  concatMapAttrs = f: attrs: foldr (a: b: a // b) { } (mapAttrsToList f attrs);

  cfg = config.fudo.acme;
  hasLocalDomains = hasAttr hostname cfg.host-domains;
  localDomains = if hasLocalDomains then cfg.host-domains.${hostname} else { };

  optionalStringOr = str: default: if (str != null) then str else default;

in {
  options.fudo.acme = with types; {
    host-domains = mkOption {
      type = attrsOf (attrsOf (submodule domainOpts));
      description = "Map of host to domains to domain options.";
      default = { };
    };

    challenge-path = mkOption {
      type = str;
      description = "Web-accessible path for responding to ACME challenges.";
      # Sigh. Leave it the same as nginx default, so it works whether or not
      # nginx feels like helping or not.
      default = "/var/lib/acme/acme-challenge";
      # default = "/run/acme-challenge";
    };
  };

  config = {
    security.acme.certs = mapAttrs (domain: domainOpts:
      {
        #   email = domainOpts.admin-email;
        #   webroot = cfg.challenge-path;
        #   group = "nginx";
        #   extraDomainNames = domainOpts.extra-domains;
      }) localDomains;

    # Assume that if we're acquiring SSL certs, we have a real IP for the
    # host. nginx must have an acme dir for security.acme to work.
    services.nginx = mkIf hasLocalDomains {
      enable = true;
      recommendedTlsSettings = true;
      virtualHosts = let server-path = "/.well-known/acme-challenge";
      in (mapAttrs (domain: domainOpts: {
        # THIS IS A HACK. Getting redundant paths. So if {domain} is configured
        # somewhere else, assume ACME is already set.
        # locations.${server-path} = mkIf (! (hasAttr domain config.services.nginx.virtualHosts)) {
        #   root = cfg.challenge-path;
        #   extraConfig = "auth_basic off;";
        # };
        enableACME = true;
        forceSSL = true;
        serverAliases = domainOpts.extra-domains;
      }) localDomains) // {
        "default" = {
          serverName = "_";
          default = true;
          locations = {
            "${server-path}" = {
              root = cfg.challenge-path;
              extraConfig = "auth_basic off;";
            };
            "/".return = "403 Forbidden";
          };
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    systemd = {
      tmpfiles = mkIf hasLocalDomains {
        rules = let
          copies = concatMapAttrs (domain: domainOpts: domainOpts.local-copies)
            localDomains;
          perms = copyOpts: if (copyOpts.group != null) then "0550" else "0500";
          copy-paths = mapAttrsToList (copy: copyOpts:
            let
              dir-entry = copyOpts: file:
                ''
                  d "${dirOf file}" ${perms copyOpts} ${copyOpts.user} ${
                    optionalStringOr copyOpts.group "-"
                  } - -'';
            in map (dir-entry copyOpts) [
              copyOpts.certificate
              copyOpts.full-certificate
              copyOpts.chain
              copyOpts.private-key
            ]) copies;
        in (unique (concatMap (i: unique i) copy-paths))
        ++ [ ''d "${cfg.challenge-path}" 755 acme nginx - -'' ];
      };

      services = concatMapAttrs (domain: domainOpts:
        concatMapAttrs (copy: copyOpts:
          let
            key-perms = copyOpts:
              if (copyOpts.group != null) then "0440" else "0400";
            source = config.security.acme.certs.${domain}.directory;
            target = copyOpts.path;
            owners = if (copyOpts.group != null) then
              "${copyOpts.user}:${copyOpts.group}"
            else
              copyOpts.user;
            dirs = unique [
              (dirOf copyOpts.certificate)
              (dirOf copyOpts.full-certificate)
              (dirOf copyOpts.chain)
              (dirOf copyOpts.private-key)
            ];
            install-certs =
              pkgs.writeShellScript "fudo-install-${domain}-${copy}-certs.sh" ''
                ${concatStringsSep "\n" (map (dir: ''
                  mkdir -p ${dir}
                  chown ${owners} ${dir}
                '') dirs)}
                cp ${source}/cert.pem ${copyOpts.certificate}
                chmod 0444 ${copyOpts.certificate}
                chown ${owners} ${copyOpts.certificate}

                cp ${source}/full.pem ${copyOpts.full-certificate}
                chmod 0444 ${copyOpts.full-certificate}
                chown ${owners} ${copyOpts.full-certificate}

                cp ${source}/chain.pem ${copyOpts.chain}
                chmod 0444 ${copyOpts.chain}
                chown ${owners} ${copyOpts.chain}

                cp ${source}/key.pem ${copyOpts.private-key}
                chmod ${key-perms copyOpts} ${copyOpts.private-key}
                chown ${owners} ${copyOpts.private-key}
              '';

            service-name = rm-service-ext copyOpts.service;
          in {
            ${service-name} = {
              description = "Copy ${domain} ACME certs for ${copy}.";
              after = [ "acme-${domain}.service" ];
              before = copyOpts.dependent-services;
              wantedBy = [ "multi-user.target" ] ++ copyOpts.dependent-services;
              partOf = copyOpts.part-of;
              serviceConfig = {
                Type = "simple";
                ExecStart = install-certs;
                RemainAfterExit = true;
                StandardOutput = "journal";
              };
            };
          }) domainOpts.local-copies) localDomains;
    };
  };
}
