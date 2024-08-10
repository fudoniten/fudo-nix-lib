{ config, lib, pkgs, ... }:

with lib;
let
  hostname = config.instance.hostname;
  domain = config.instance.local-domain;

  domainOpts = { name, ... }:
    let domain = name;
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

        metrics = mkOption {
          type = nullOr (submodule {
            options = {
              grafana-host = mkOption {
                type = str;
                description = "Hostname of the Grafana Metrics Analysis tool.";
              };
              prometheus-host = mkOption {
                type = str;
                description =
                  "Hostname of the Prometheus Metrics Aggregator tool.";
              };
            };
          });
          default = null;
        };

        log-aggregator = mkOption {
          type = nullOr str;
          description = "Host which will accept incoming log pushes.";
          default = null;
        };

        postgresql-server = mkOption {
          type = nullOr str;
          description = "Hostname acting as the local PostgreSQL server.";
          default = null;
        };

        chat-server = mkOption {
          type = nullOr str;
          description =
            "Hostname acting as the domain chat server (using Mattermost).";
          default = null;
        };

        kubernetes = let
          kubeOpts.options = {
            masters = mkOption {
              type = listOf str;
              description = "Master Kubernetes hosts.";
            };

            nodes = mkOption {
              type = listOf str;
              description = "List of Kubernetes nodes.";
            };
          };
        in mkOption {
          type = nullOr (submodule kubeOpts);
          description = "Kubernetes configuration.";
          default = null;
        };

        backplane = mkOption {
          type = nullOr (submodule {
            options = {
              nameserver = mkOption {
                type = nullOr str;
                description = "Host acting as backplane dynamic DNS server.";
                default = null;
              };

              dns-service = mkOption {
                type = nullOr str;
                description = "DNS backplane service host.";
                default = null;
              };

              domain = mkOption {
                type = str;
                description =
                  "Domain name of the dynamic zone served by this server.";
              };
            };
          });
          description = "Backplane configuration.";
          default = null;
        };

        wireguard = {
          gateway = mkOption {
            type = str;
            description = "Host serving as WireGuard gateway for this domain.";
          };

          network = mkOption {
            type = str;
            description = "IP subnet used for WireGuard clients.";
            default = "172.16.0.0/16";
          };

          routed-network = mkOption {
            type = nullOr str;
            description = "Subnet of larger network for which we NAT traffic.";
            default = "172.16.16.0/20";
          };
        };

        gssapi-realm = mkOption {
          type = nullOr str;
          description = "GSSAPI (i.e. Kerberos) realm of this domain.";
          default = null;
        };

        kerberos-master = mkOption {
          type = nullOr str;
          description =
            "Hostname of the Kerberos master server for the domain, if applicable.";
          default = null;
        };

        kerberos-slaves = mkOption {
          type = listOf str;
          description =
            "List of hosts acting as Kerberos slaves for the domain.";
          default = [ ];
        };

        ldap-servers = mkOption {
          type = listOf str;
          description =
            "List of hosts acting as LDAP authentication servers for the domain.";
          default = [ ];
        };

        primary-nameserver = mkOption {
          type = nullOr str;
          description = "Hostname of the primary nameserver for this domain.";
          default = null;
        };

        secondary-nameservers = mkOption {
          type = listOf str;
          description =
            "List of hostnames of slave nameservers for this domain.";
          default = [ ];
        };

        primary-mailserver = mkOption {
          type = nullOr str;
          description = "Hostname of the primary mail server for this domain.";
          default = null;
        };

        xmpp-servers = mkOption {
          type = listOf str;
          description = "Hostnames of the domain XMPP servers.";
          default = [ ];
        };

        zone = mkOption {
          type = nullOr str;
          description = "Name of the DNS zone associated with domain.";
          default = null;
        };

        nexus = {
          public-domains = mkOption {
            type = listOf str;
            description = "Nexus domains to which hosts in this domain belong.";
            default = [ ];
          };

          private-domains = mkOption {
            type = listOf str;
            description =
              "Nexus private domains to which hosts in this domain belong.";
            default = [ ];
          };

          tailscale-domains = mkOption {
            type = listOf str;
            description =
              "Nexus tailscale domains to which hosts in this domain belong.";
            default = [ ];
          };
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
