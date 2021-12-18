{ config, lib, pkgs, ... }:

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

  stageOpts = { ... }: {
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

      credential-file = mkOption {
        type = str;
        description = ''
          Path to a host-local env file containing definitions for:

          COINBASE_API_HOSTNAME
          COINBASE_API_SECRET
          COINBASE_API_PASSPHRASE
          COINBASE_API_KEY
        '';
      };
    };
  };

  concatMapAttrs = f: attrs:
    foldr (a: b: a // b) {} (mapAttrsToList f attrs);

  chute-job-definition = { stage, credential-file, currency, stop-at-percent, package }: {
    after = [ "network-online.target" ];
    wantedBy = [ "chute.target" ];
    partOf = [ "chute.target" ];
    description = "Chute ${stage} job for ${currency}";
    path = [ package ];
    environmentFile = credential-file;
    execStart = "${package}/bin/chute --currency=${currency} --stop-at-percent=${toString stop-at-percent}";
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
          credential-file = "/path/to/credentials-file";
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
            inherit stage currency;
            credential-file = stageOpts.credential-file;
            package = stageOpts.package;
            stop-at-percent = currencyOpts.stop-percentile;
          };
        }) stageOpts.currencies) cfg.stages;
    };

    systemd.targets.chute = {
      wantedBy = [ "multi-user.target" ];
      description = "Chute cryptocurrency safety parachute.";
    };
  };
}
