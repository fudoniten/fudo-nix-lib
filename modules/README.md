# Fudo NixOS Module Groups

This directory contains modular groupings of the Fudo NixOS library, allowing you to import only the services your hosts need.

## Why Modular?

Instead of importing all 50+ modules on every host, you can now selectively import only what you need. This provides:

- **Faster evaluation** - NixOS only evaluates modules you import
- **Clearer host roles** - Imports document what each host does
- **Better deploy-rs performance** - Smaller evaluation scope for targeted deployments
- **Explicit dependencies** - Clear which services depend on what

## Available Module Groups

### `core` (Required on all hosts)
Foundational configuration that all services depend on:
- Host, site, domain, and zone definitions
- User and group management
- Secret management infrastructure
- System-level configuration

**Always import this module.**

### `auth`
Authentication and identity management services:
- LDAP server (directory service)
- LDAP client authentication
- Kerberos KDC (optional)
- SSH server configuration
- Password management

**Dependencies:** core

### `dns`
DNS server and client infrastructure:
- NSD (authoritative DNS server)
- PowerDNS (authoritative DNS with database backend)
- Local network services (DHCP + dnsmasq for dynamic DNS)
- DNS client configuration
- DNS proxy services (AdGuard, secure DNS)

**Dependencies:** core
**Optional:** messaging (for backplane DNS service), infrastructure (for PostgreSQL if using PowerDNS)

### `infrastructure`
Core infrastructure and deployment services:
- PostgreSQL database (used by mail, DNS, chat, etc.)
- ACME/Let's Encrypt certificate management
- Deployment orchestration (deploy-rs integration)
- Distributed Nix builds
- Encrypted filesystem management
- Network interface configuration
- VPN services (OpenVPN and WireGuard)
- Wireless network configuration
- Garbage collection/cleanup

**Dependencies:** core

### `mail`
Email server infrastructure:
- Mail server orchestration (postfix, dovecot, rspamd, clamav, dkim)
- Containerized mail deployment option
- Webmail interface

**Dependencies:** core, auth (for LDAP), infrastructure (for PostgreSQL)

### `messaging`
XMPP-based messaging infrastructure:
- Backplane (inter-service messaging/coordination)
- Jabber server (XMPP server implementation)

**Dependencies:** core

### `monitoring`
Monitoring and metrics infrastructure:
- Prometheus (metrics collection and storage)
- Grafana (metrics visualization and dashboards)
- Node exporter (host metrics)

**Dependencies:** core
**Optional:** auth (for LDAP authentication in Grafana)

### `services`
Various application and development services:
- Chat (Mattermost team collaboration)
- Git (version control hosting)
- IPFS (distributed file storage)
- Nexus (software repository manager)
- Minecraft servers (both Java and Clojure-based)
- Network info via email
- Slynk (Common Lisp REPL server)

**Dependencies:** core
**Optional:** infrastructure (for PostgreSQL), auth (for LDAP integration)

### `full`
All modules combined (backwards compatibility). Use this if you want the old behavior of importing everything.

**Not recommended for new deployments.**

## Usage Examples

### Example 1: DNS-only Server

```nix
# hosts/dns1.nix
{ config, ... }: {
  imports = [
    fudo-nix-lib.nixosModules.core
    fudo-nix-lib.nixosModules.dns
    fudo-nix-lib.nixosModules.infrastructure  # For PowerDNS + PostgreSQL
  ];

  # Your host-specific configuration
  instance = {
    hostname = "dns1";
    local-domain = "example.com";
    # ...
  };

  fudo.powerdns.enable = true;
  fudo.nsd.enable = false;
}
```

### Example 2: Authentication Server

```nix
# hosts/auth1.nix
{ config, ... }: {
  imports = [
    fudo-nix-lib.nixosModules.core
    fudo-nix-lib.nixosModules.auth
  ];

  instance = {
    hostname = "auth1";
    # ...
  };

  fudo.auth.ldap-server.enable = true;
  fudo.auth.kerberos.enable = true;
}
```

### Example 3: Mail Server

```nix
# hosts/mail1.nix
{ config, ... }: {
  imports = [
    fudo-nix-lib.nixosModules.core
    fudo-nix-lib.nixosModules.auth         # For LDAP authentication
    fudo-nix-lib.nixosModules.infrastructure  # For PostgreSQL
    fudo-nix-lib.nixosModules.mail
  ];

  instance = {
    hostname = "mail1";
    # ...
  };

  fudo.mail-server.enable = true;
}
```

### Example 4: Monitoring Stack

```nix
# hosts/monitor1.nix
{ config, ... }: {
  imports = [
    fudo-nix-lib.nixosModules.core
    fudo-nix-lib.nixosModules.monitoring
  ];

  instance = {
    hostname = "monitor1";
    # ...
  };

  fudo.metrics.prometheus.enable = true;
  fudo.metrics.grafana.enable = true;
}
```

### Example 5: All-in-One Server

```nix
# hosts/everything.nix
{ config, ... }: {
  imports = [
    # Option A: Import everything explicitly
    fudo-nix-lib.nixosModules.core
    fudo-nix-lib.nixosModules.auth
    fudo-nix-lib.nixosModules.dns
    fudo-nix-lib.nixosModules.infrastructure
    fudo-nix-lib.nixosModules.mail
    fudo-nix-lib.nixosModules.messaging
    fudo-nix-lib.nixosModules.monitoring
    fudo-nix-lib.nixosModules.services

    # Option B: Or just use full (backwards compatibility)
    # fudo-nix-lib.nixosModules.full
  ];

  # ...
}
```

## Migration Guide

### From Monolithic to Modular

If you're currently using:

```nix
imports = [ fudo-nix-lib.nixosModules.default ];
```

You have two options:

**Option 1: Keep using `full` (no changes needed)**
```nix
imports = [ fudo-nix-lib.nixosModules.full ];
```

**Option 2: Migrate to selective imports**

1. Identify which services your host actually uses
2. Import `core` plus the relevant module groups
3. Test that your configuration still builds
4. Deploy with `deploy-rs`

Example migration for a host running just DNS and monitoring:

```diff
 { config, ... }: {
   imports = [
-    fudo-nix-lib.nixosModules.default
+    fudo-nix-lib.nixosModules.core
+    fudo-nix-lib.nixosModules.dns
+    fudo-nix-lib.nixosModules.infrastructure  # For PostgreSQL
+    fudo-nix-lib.nixosModules.monitoring
   ];
```

## Using with deploy-rs

With modular imports, deploy-rs becomes more efficient:

```nix
# flake.nix in your deployment repo
{
  outputs = { self, nixpkgs, deploy-rs, fudo-nix-lib, ... }: {
    nixosConfigurations = {
      # DNS server - only evaluates core + dns + infrastructure
      dns1 = nixpkgs.lib.nixosSystem {
        modules = [
          fudo-nix-lib.nixosModules.core
          fudo-nix-lib.nixosModules.dns
          fudo-nix-lib.nixosModules.infrastructure
          ./hosts/dns1.nix
        ];
      };

      # Auth server - only evaluates core + auth
      auth1 = nixpkgs.lib.nixosSystem {
        modules = [
          fudo-nix-lib.nixosModules.core
          fudo-nix-lib.nixosModules.auth
          ./hosts/auth1.nix
        ];
      };
    };

    deploy.nodes = {
      dns1 = {
        hostname = "dns1.example.com";
        profiles.system = {
          path = deploy-rs.lib.x86_64-linux.activate.nixos
            self.nixosConfigurations.dns1;
        };
      };
      # ...
    };
  };
}
```

## Dependency Graph

```
core (always required)
 ├── auth
 ├── dns
 │   └── infrastructure (optional, for PowerDNS + PostgreSQL)
 ├── infrastructure
 ├── mail
 │   ├── auth (for LDAP)
 │   └── infrastructure (for PostgreSQL)
 ├── messaging
 ├── monitoring
 │   └── auth (optional, for Grafana LDAP)
 └── services
     ├── infrastructure (optional, for PostgreSQL)
     └── auth (optional, for LDAP)
```

## Module Contents Reference

<details>
<summary><b>core</b> - Modules included</summary>

- `domains.nix` - Domain configuration
- `hosts.nix` - Host definitions
- `secrets.nix` - Secret management
- `sites.nix` - Site/location configuration
- `system.nix` - System-level settings
- `users.nix` - User and group definitions
- `zones.nix` - DNS zone and network IP mappings

</details>

<details>
<summary><b>auth</b> - Modules included</summary>

- `auth/` - Kerberos and authentication services
- `authentication.nix` - LDAP client configuration
- `ldap.nix` - LDAP server (OpenLDAP)
- `password.nix` - Password management utilities
- `ssh.nix` - SSH server configuration

</details>

<details>
<summary><b>dns</b> - Modules included</summary>

- `adguard-dns-proxy.nix` - AdGuard DNS proxy
- `backplane-service/dns.nix` - Backplane DNS integration
- `client/dns.nix` - DNS client configuration
- `dns.nix` - DNS server orchestration
- `local-network.nix` - DHCP + dnsmasq (dynamic DNS)
- `nsd.nix` - NSD authoritative DNS server
- `powerdns.nix` - PowerDNS with PostgreSQL backend
- `secure-dns-proxy.nix` - Secure DNS proxy

</details>

<details>
<summary><b>infrastructure</b> - Modules included</summary>

- `acme-certs.nix` - ACME/Let's Encrypt certificates
- `deploy.nix` - Deployment orchestration
- `distributed-builds.nix` - Nix distributed builds
- `garbage-collector.nix` - Storage cleanup
- `host-filesystems.nix` - Encrypted filesystem management
- `postgres.nix` - PostgreSQL database server
- `system-networking.nix` - Network interface configuration
- `vpn.nix` - VPN services
- `wireless-networks.nix` - Wireless network configuration

</details>

<details>
<summary><b>mail</b> - Modules included</summary>

- `mail.nix` - Mail server orchestration
- `mail-container.nix` - Containerized mail deployment
- `webmail.nix` - Webmail interface

Note: The mail.nix module imports subdirectory modules (postfix, dovecot, rspamd, clamav, dkim) automatically.

</details>

<details>
<summary><b>messaging</b> - Modules included</summary>

- `backplane.nix` - Inter-service messaging infrastructure
- `jabber.nix` - XMPP/Jabber server

</details>

<details>
<summary><b>monitoring</b> - Modules included</summary>

- `grafana.nix` - Grafana dashboards
- `node-exporter.nix` - Prometheus node exporter
- `prometheus.nix` - Prometheus metrics server

</details>

<details>
<summary><b>services</b> - Modules included</summary>

- `chat.nix` - Mattermost chat server
- `git.nix` - Git hosting services
- `ipfs.nix` - IPFS distributed storage
- `minecraft-clj.nix` - Clojure-based Minecraft server
- `minecraft-server.nix` - Java Minecraft server
- `netinfo-email.nix` - Network info via email
- `nexus.nix` - Nexus repository manager
- `slynk.nix` - Common Lisp REPL server

</details>

## Questions?

If you're unsure which modules to import for a specific host:

1. Always import `core`
2. Import module groups for the services you're actually enabling
3. Check the dependency notes in each module group header
4. Look at the examples above for similar use cases

## Backwards Compatibility

The `default` and `fudo` module outputs continue to work exactly as before - they import the `full` module collection. Existing configurations require no changes.
