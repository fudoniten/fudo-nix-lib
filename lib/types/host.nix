{ lib, ... }:

with lib;
let passwd = import ../passwd.nix { inherit lib; };

in rec {
  encryptedFSOpts = { name, ... }:
    let
      mountpoint = { name, ... }: {
        options = with types; {
          mountpoint = mkOption {
            type = str;
            description = "Path at which to mount the filesystem.";
            default = name;
          };

          options = mkOption {
            type = listOf str;
            description =
              "List of filesystem options specific to this mountpoint (eg: subvol).";
            default = [ ];
          };

          group = mkOption {
            type = nullOr str;
            description = "Group to which the mountpoint should belong.";
            default = null;
          };

          users = mkOption {
            type = listOf str;
            description = ''
              List of users who should have access to the filesystem.

              Requires a group to be set.
            '';
            default = [ ];
          };

          world-readable = mkOption {
            type = bool;
            description = "Whether to leave the top level world-readable.";
            default = true;
          };
        };
      };
    in {
      options = with types; {
        encrypted-device = mkOption {
          type = str;
          description = "Path to the encrypted device.";
        };

        key-path = mkOption {
          type = str;
          description = ''
            Path at which to locate the key file.

            The filesystem will be decrypted and mounted once available.";
          '';
        };

        type = mkOption {
          type = enum [ "luks" "luks2" ];
          description = "Type of the LUKS encryption.";
          default = "luks";
        };

        remove-key = mkOption {
          type = bool;
          description = "Remove key once the filesystem is decrypted.";
          default = true;
        };

        filesystem-type = mkOption {
          type = str;
          description = "Filesystem type of the decrypted filesystem.";
        };

        options = mkOption {
          type = listOf str;
          description = "List of filesystem options with which to mount.";
          default = [ ];
        };

        mountpoints = mkOption {
          type = attrsOf (submodule mountpoint);
          description =
            "A map of mountpoints for this filesystem to fs options. Multiple to support btrfs.";
          default = { };
        };
      };
    };

  masterKeyOpts = { ... }: {
    options = with types; {
      key-path = mkOption {
        type = str;
        description =
          "Path of the host master key file, used to decrypt secrets.";
      };

      public-key = mkOption {
        type = str;
        description =
          "Public key used during deployment to decrypt secrets for the host.";
      };
    };
  };

  hostOpts = { name, ... }:
    let hostname = name;
    in {
      options = with types; {
        master-key = mkOption {
          type = nullOr (submodule masterKeyOpts);
          description =
            "Public key for the host master key, used by the host to decrypt secrets.";
        };

        domain = mkOption {
          type = str;
          description =
            "Primary domain to which the host belongs, in the form of a domain name.";
          default = "fudo.org";
        };

        extra-domains = mkOption {
          type = listOf str;
          description = "Extra domain in which this host is reachable.";
          default = [ ];
        };

        aliases = mkOption {
          type = listOf str;
          description =
            "Host aliases used by the current host. Note this will be multiplied with extra-domains.";
          default = [ ];
        };

        site = mkOption {
          type = str;
          description = "Site at which the host is located.";
          default = "unsited";
        };

        local-networks = mkOption {
          type = listOf str;
          description =
            "A list of networks to be considered trusted by this host.";
          default = [ "127.0.0.0/8" ];
        };

        profile = mkOption {
          type = listOf (enum [ "desktop" "server" "laptop" ]);
          description =
            "The profile to be applied to the host, determining what software is included.";
        };

        admin-email = mkOption {
          type = nullOr str;
          description = "Email for the administrator of this host.";
          default = null;
        };

        local-users = mkOption {
          type = listOf str;
          description =
            "List of users who should have local (i.e. login) access to the host.";
          default = [ ];
        };

        description = mkOption {
          type = str;
          description = "Description of this host.";
          default = "Another Fudo Host.";
        };

        local-admins = mkOption {
          type = listOf str;
          description =
            "A list of users who should have admin access to this host.";
          default = [ ];
        };

        local-groups = mkOption {
          type = listOf str;
          description = "List of groups which should exist on this host.";
          default = [ ];
        };

        ssh-fingerprints = mkOption {
          type = listOf str;
          description = ''
            A list of DNS SSHFP records for this host. Get with `ssh-keygen -r <hostname>`
          '';
          default = [ ];
        };

        rp = mkOption {
          type = nullOr str;
          description = "Responsible person.";
          default = null;
        };

        tmp-on-tmpfs = mkOption {
          type = bool;
          description =
            "Use tmpfs for /tmp. Great if you've got enough (>16G) RAM.";
          default = true;
        };

        enable-gui = mkEnableOption "Install desktop GUI software.";

        docker-server = mkEnableOption "Enable Docker on the current host.";

        kerberos-services = mkOption {
          type = listOf str;
          description =
            "List of services which should exist for this host, if it belongs to a realm.";
          default = [ "ssh" "host" ];
        };

        ssh-pubkeys = mkOption {
          type = listOf path;
          description = "SSH key files of the host.";
          default = [ ];
        };

        build-pubkeys = mkOption {
          type = listOf str;
          description = "SSH public keys used to access the build server.";
          default = [ ];
        };

        external-interfaces = mkOption {
          type = listOf str;
          description = "A list of interfaces on which to enable the firewall.";
          default = [ ];
        };

        keytab-secret-file = mkOption {
          type = nullOr str;
          description = "Keytab from which to create a keytab secret.";
          default = null;
        };

        keep-cool = mkOption {
          type = bool;
          description = "A host that tends to overheat. Try to keep it cooler.";
          default = false;
        };

        nixos-system = mkOption {
          type = bool;
          description = "Whether the host is a NixOS system.";
          default = true;
        };

        arch = mkOption {
          type = str;
          description = "System architecture of the system.";
        };

        machine-id = mkOption {
          type = nullOr str;
          description = "Machine id of the system. See: man machine-id.";
          default = null;
        };

        android-dev = mkEnableOption "Enable ADB on the host.";

        encrypted-filesystems = mkOption {
          type = attrsOf (submodule encryptedFSOpts);
          description =
            "List of encrypted filesystems to mount on the local host when the key is available.";
          default = { };
        };

        hardened = mkOption {
          type = bool;
          description = "Harden the host, applying additional security.";
          default = false;
        };

        wireguard = let
          clientOpts = {
            options = {
              ip = mkOption {
                type = nullOr str;
                description =
                  "IP address assigned to this host in the WireGuard network.";
              };

              bound = mkOption {
                type = bool;
                description = "Whether to route all traffic from this host.";
                default = false;
              };
            };
          };

          wireguardOpts = {
            options = {
              private-key-file = mkOption {
                type = str;
                description = "WireGuard private key file of the host.";
              };

              public-key = mkOption {
                type = str;
                description = "WireGuard public key.";
              };

              client = mkOption {
                type = nullOr (submodule clientOpts);
                default = null;
              };
            };
          };
        in mkOption {
          type = nullOr (submodule wireguardOpts);
          default = null;
        };

        initrd-network = let
          keypair-type = { ... }: {
            options = {
              public-key = mkOption {
                type = str;
                description = "SSH public key.";
              };

              private-key-file = mkOption {
                type = str;
                description = "Path to SSH private key (on the local host!).";
              };
            };
          };

          initrd-network-config = { ... }: {
            options = {
              ip = mkOption {
                type = str;
                description =
                  "IP to assign to the initrd image, allowing access to host during bootup.";
              };
              keypair = mkOption {
                type = (submodule keypair-type);
                description = "SSH host key pair to use for initrd.";
              };
              interface = mkOption {
                type = str;
                description =
                  "Name of interface on which to listen for connections.";
              };
            };
          };

        in mkOption {
          type = nullOr (submodule initrd-network-config);
          description =
            "Configuration parameters to set up initrd SSH network.";
          default = null;
        };

        backplane-password-file = mkOption {
          type = path;
          description =
            "File containing the password used by this host to connect to the backplane.";
        };
      };
    };
}
