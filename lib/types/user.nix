{ lib, ... }:

with lib;
rec {
  systemUserOpts = { name, ... }: {
    options = with lib.types; {
      username = mkOption {
        type = str;
        description = "The system user's login name.";
        default = name;
      };

      description = mkOption {
        type = str;
        description = "Description of this system user's purpose or role";
      };

      ldap-hashed-password = mkOption {
        type = str;
        description =
          "LDAP-formatted hashed password for this user. Generate with slappasswd.";
      };
    };
  };

  userOpts = { name, ... }: let
    username = name;
  in {
    options = with lib.types; {
      username = mkOption {
        type = str;
        description = "The user's login name.";
        default = username;
      };

      uid = mkOption {
        type = int;
        description = "Unique UID number for the user.";
      };

      common-name = mkOption {
        type = str;
        description = "The user's common or given name.";
      };

      primary-group = mkOption {
        type = str;
        description = "Primary group to which the user belongs.";
      };

      login-shell = mkOption {
        type = nullOr shellPackage;
        description = "The user's preferred shell.";
      };

      description = mkOption {
        type = str;
        default = "Fudo Member";
        description = "A description of this user's role.";
      };

      ldap-hashed-passwd = mkOption {
        type = nullOr str;
        description =
          "LDAP-formatted hashed password, used for email and other services. Use slappasswd to generate the properly-formatted password.";
        default = null;
      };

      login-hashed-passwd = mkOption {
        type = nullOr str;
        description =
          "Hashed password for shell, used for shell access to hosts. Use mkpasswd to generate the properly-formatted password.";
        default = null;
      };

      ssh-authorized-keys = mkOption {
        type = listOf str;
        description = "SSH public keys this user can use to log in.";
        default = [ ];
      };

      home-directory = mkOption {
        type = nullOr str;
        description = "Default home directory for the given user.";
        default = null;
      };

      k5login = mkOption {
        type = listOf str;
        description = "List of Kerberos principals that map to this user.";
        default = [ ];
      };

      ssh-keys = mkOption {
        type = listOf (submodule sshKeyOpts);
        description = "Path to the user's public and private key files.";
        default = [];
      };

      email = mkOption {
        type = nullOr str;
        description = "User's primary email address.";
        default = null;
      };

      email-aliases = mkOption {
        type = listOf str;
        description = "Email aliases that should map to this user.";
        default = [];
      };
    };
  };

  groupOpts = { name, ... }: {
    options = with lib.types; {
      group-name = mkOption {
        description = "Group name.";
        default = name;
      };

      description = mkOption {
        type = str;
        description = "Description of the group or it's purpose.";
      };

      members = mkOption {
        type = listOf str;
        default = [ ];
        description = "A list of users who are members of the current group.";
      };

      gid = mkOption {
        type = int;
        description = "GID number of the group.";
      };
    };
  };

  sshKeyOpts = { ... }: {
    options = with lib.types; {
      private-key = mkOption {
        type = str;
        description = "Path to the user's private key.";
      };

      public-key = mkOption {
        type = str;
        description = "Path to the user's public key.";
      };

      key-type = mkOption {
        type = enum [ "rsa" "ecdsa" "ed25519" ];
        description = "Type of the user's public key.";
      };
    };
  };
}
