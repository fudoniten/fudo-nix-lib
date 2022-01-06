{ config, lib, pkgs, ... } @ toplevel:

with lib;
let
  cfg = config.informis.chute;

  currencyOpts = { ... }: {
    options = with types; {
      stop-percentile = mkOption {
        type = int;
        description = "Percentile of observed max at which to sell.";
      };
    };
  };

  stageOpts = { name, ... }: let
    stage-name = name;
  in {
    options = with types; {
      currencies = mkOption {
        type = attrsOf (submodule currencyOpts);
        description = "Map of cryptocurrencies to chute currency settings.";
      };

      package = mkOption {
        type = package;
        description = "Chute package to use for this stage.";
        default = pkgs.chute;
      };

      environment-file = mkOption {
        type = str;
        description = ''
          Path to a host-local env file containing definitions for:

          COINBASE_API_HOSTNAME
          COINBASE_API_SECRET
          COINBASE_API_PASSPHRASE
          COINBASE_API_KEY
          JABBER_PASSWORD (optional)
        '';
      };

      jabber = {
        jid = mkOption {
          type = str;
          description = "Jabber JID as which to connect.";
          example = "chute-user@my.domain.org";
          default = null;
        };

        resource = mkOption {
          type = str;
          description = "Jabber resource string.";
          default = "${toplevel.config.instance.hostname}-${stage-name}";
        };

        target-jid = mkOption {
          type = str;
          description = "User to which logs will be sent.";
          example = "target@my.domain.org";
          default = null;
        };
      };
    };
  };

  concatMapAttrs = f: attrs:
    foldr (a: b: a // b) {} (mapAttrsToList f attrs);

  chute-job-definition = { stage, currency, stageOpts, currencyOpts }: let
    join-args = concatStringsSep " ";
  in {
    after = [ "network-online.target" ];
    wantedBy = [ "chute.target" ];
    partOf = [ "chute.target" ];
    description = "Chute ${stage} job for ${currency}";
    environmentFile = stageOpts.environment-file;
    execStart = let
      jabber-string =
        optionalString (stageOpts.jabber != null)
          (join-args  ["--jabber-jid=${stageOpts.jabber.jid}"
                       "--target-jid=${stageOpts.jabber.target-jid}"
                       "--jabber-resource=${stageOpts.jabber.resource}-${currency}"]);

    in join-args ["${stageOpts.package}/bin/chute"
                  "--currency=${currency}"
                  "--stop-at-percent=${toString currencyOpts.stop-percentile}"
                  jabber-string];
    privateNetwork = false;
    addressFamilies = [ "AF_INET" ];
    memoryDenyWriteExecute = false; # Needed becuz Clojure
  };

in {
  options.informis.chute = with types; {
    enable = mkEnableOption "Enable Chute cryptocurrency parachute.";

    stages = mkOption {
      type = attrsOf (submodule stageOpts);
      description = "Map of stage names to stage options.";
      example = {
        staging = {
          environment-file = "/path/to/environment-file";
          currencies = {
            btc.stop-percentile = 90;
            ada.stop-percentile = 85;
          };
        };
      };
      default = {};
    };
  };

  config = mkIf (cfg.enable) {
    fudo = {
      system.services = concatMapAttrs (stage: stageOpts:
        concatMapAttrs (currency: currencyOpts: {
          "chute-${stage}-${currency}" = chute-job-definition {
            inherit stage currency stageOpts currencyOpts;
          };
        }) stageOpts.currencies) cfg.stages;
    };

    systemd.targets.chute = {
      wantedBy = [ "multi-user.target" ];
      description = "Chute cryptocurrency safety parachute.";
    };
  };
}
