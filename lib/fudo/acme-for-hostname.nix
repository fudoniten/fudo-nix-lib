# Starts an Nginx server on $HOSTNAME just to get a cert for this host

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.acme;

  # wwwRoot = hostname:
  #   pkgs.writeTextFile {
  #     name = "index.html";

  #     text = ''
  #       <html>
  #         <head>
  #           <title>${hostname}</title>
  #         </head>
  #         <body>
  #           <h1>${hostname}</title>
  #         </body>
  #       </html>
  #     '';
  #     destination = "/www";
  #   };

in {

  options.fudo.acme = {
    enable = mkEnableOption "Fetch ACME certs for supplied local hostnames.";

    hostnames = mkOption {
      type = with types; listOf str;
      description = "A list of hostnames mapping to this host, for which to acquire SSL certificates.";
      default = [];
      example = [
        "my.hostname.com"
        "alt.hostname.com"
      ];
    };

    admin-address = mkOption {
      type = types.str;
      description = "The admin address in charge of these addresses.";
      default = "admin@fudo.org";
    };
  };

  config = mkIf cfg.enable {

    services.nginx = {
      enable = true;

      virtualHosts = listToAttrs
        (map
          (hostname:
            nameValuePair hostname
              {
                enableACME = true;
                forceSSL = true;
                # root = (wwwRoot hostname) + ("/" + "www");
              })
          cfg.hostnames);
    };

    security.acme.certs = listToAttrs
      (map (hostname: nameValuePair hostname { email = cfg.admin-address; })
        cfg.hostnames);
  };
}
