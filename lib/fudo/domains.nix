{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;
  domain = config.instance.local-domain;

  domainOpts = { name, ... }: let
    domain = name;
  in {
    options = with types; {
      domain = mkOption {
        type = str;
        description = "Domain name.";
        default = domain;
      };

      local-networks = mkOption {
        type = listOf str;
        description =
          "A list of networks to be considered trusted on this network.";
        default = [ ];
      };

      local-users = mkOption {
        type = listOf str;
        description =
          "A list of users who should have local (i.e. login) access to _all_ hosts in this domain.";
        default = [ ];
      };

      local-admins = mkOption {
        type = listOf str;
        description =
          "A list of users who should have admin access to _all_ hosts in this domain.";
        default = [ ];
      };

      local-groups = mkOption {
        type = listOf str;
        description = "List of groups which should exist within this domain.";
        default = [ ];
      };

      admin-email = mkOption {
        type = str;
        description = "Email for the administrator of this domain.";
        default = "admin@${domain}";
      };

      gssapi-realm = mkOption {
        type = nullOr str;
        description = "GSSAPI (i.e. Kerberos) realm of this domain.";
        default = null;
      };

      kerberos-master = mkOption {
        type = nullOr str;
        description = "Hostname of the Kerberos master server for the domain, if applicable.";
        default = null;
      };

      kerberos-slaves = mkOption {
        type = listOf str;
        description = "List of hosts acting as Kerberos slaves for the domain.";
        default = [];
      };

      ldap-servers = mkOption {
        type = listOf str;
        description = "List of hosts acting as LDAP authentication servers for the domain.";
        default = [];
      };

      primary-nameserver = mkOption {
        type = nullOr str;
        description = "Hostname of the primary nameserver for this domain.";
        default = null;
      };

      secondary-nameservers = mkOption {
        type = listOf str;
        description = "List of hostnames of slave nameservers for this domain.";
        default = [];
      };

      primary-mailserver = mkOption {
        type = nullOr str;
        description = "Hostname of the primary mail server for this domain.";
        default = null;
      };

      xmpp-servers = mkOption {
        type = listOf str;
        description = "Hostnames of the domain XMPP servers.";
        default = [];
      };

      zone = mkOption {
        type = nullOr str;
        description = "Name of the DNS zone associated with domain.";
        default = null;
      };
    };
  };

in {
  options.fudo.domains = mkOption {
    type = with types; attrsOf (submodule domainOpts);
    description = "Domain configurations for all domains known to the system.";
    default = { };
  };
}
