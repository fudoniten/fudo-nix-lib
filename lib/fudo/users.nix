{ config, lib, pkgs, ... }:

with lib;
let
  user = import ../types/user.nix { inherit lib; };

in {
  options = with types; {
    fudo = {
      users = mkOption {
        type = attrsOf (submodule user.userOpts);
        description = "Users";
        default = { };
      };

      groups = mkOption {
        type = attrsOf (submodule user.groupOpts);
        description = "Groups";
        default = { };
      };

      system-users = mkOption {
        type = attrsOf (submodule user.systemUserOpts);
        description = "System users (probably not what you're looking for!)";
        default = { };
      };
    };
  };
}
