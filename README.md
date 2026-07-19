# fudo-nix-lib

Personal NixOS module and utility library for managing infrastructure across domains, sites, and hosts.

**Status**: Monorepo in process of being decomposed into reusable flakes.

**Audience**: Personal reference for infrastructure management and extraction planning.

---

## Quick Stats

- **~7,300 lines** of Nix code
- **33 modules** in the `fudo.*` / `informis.*` namespaces
- **6 utility libraries** (pure functions)
- **4 type definitions** (configuration schemas)
- The obsolete mail/VPN/local-network/placeholder modules (~1,850 lines) have
  now been removed — see [TODO.md](./TODO.md) for history and the remaining
  extraction plan.

---

## Repository Structure

```
lib/
├── fudo/              # Infrastructure modules (fudo.* namespace)
│   ├── auth/          # Authentication (Kerberos client + KDC)
│   ├── include/       # Included configuration fragments (e.g. rainloop)
│   └── *.nix          # Service/infra modules (postgres, git, grafana, …)
├── informis/          # Personal/experimental modules (informis.* namespace)
├── lib/               # Utility libraries (pure functions)
├── types/             # Type definitions for configuration
├── default.nix        # Module aggregator
└── instance.nix       # Per-instance configuration

flake.nix              # Flake interface
lib.nix                # Library function exports (→ pkgs.lib.*)
module.nix             # NixOS module entry point
overlay.nix            # Nixpkgs overlay
```

---

## ✅ Removed (formerly obsolete)

The following modules were verified obsolete and have now been **removed** from
the tree. They are listed here so old references make sense; see
[TODO.md](./TODO.md) for the full history.

- **Mail stack (~1,500 lines)** – superseded by the `mail-server` flake
  (`github:fudoniten/nix-mail-server`, which provides `fudo.mail.*`). This was
  `lib/fudo/mail.nix`, `lib/fudo/mail-container.nix`, and the entire
  `lib/fudo/mail/` subdirectory (postfix, dovecot, rspamd, clamav, dkim, sieve).
- **VPN module (~200 lines)** – `lib/fudo/vpn.nix` (WireGuard); never used.
- **Local network module (~144 lines)** – `lib/fudo/hosts/local-network.nix`;
  superseded by `nixos-config/config/service/local-network/`.
- **Empty placeholder** – `lib/fudo/common.nix`.

---

## Active Modules

### Core Infrastructure

Configuration models for multi-level infrastructure organization.

#### `instance.nix` - Per-Host Instance Configuration
Defines the current host's identity and context.

**Options**: `instance.*`
- `hostname`, `host-fqdn`, `local-domain`, `local-site`, `local-zone`
- `local-admins`, `local-groups`, `local-hosts`, `local-users`
- `local-networks`, `build-timestamp`, `build-seed`

**Use case**: Provides context for all other modules to adapt to current host.

#### `domains.nix` - Domain-Level Configuration
Organizational domains with their infrastructure services.

**Options**: `fudo.domains.<domain>.*`
- Network trust: `local-networks`, `local-users`, `local-admins`
- Services: `postgresql-server`, `chat-server`, `metrics`, `log-aggregator`
- Auth: `gssapi-realm`, `kerberos-master`, `ldap-servers`
- Network: `wireguard`, `nexus` (DDNS domains)
- DNS: `primary-nameserver`, `secondary-nameservers`
- Mail: `primary-mailserver`, `xmpp-servers`

**Use case**: Define domain-wide services and policies. Example: "fudo.org domain uses these Kerberos servers and mail server."

#### `hosts.nix` - Host Inventory
Attributes and configuration for all known hosts.

**Options**: `fudo.hosts.<hostname>.*`
- Identity: `domain`, `site`, `description`, `aliases`
- Network: `local-networks`, `external-interfaces`
- Access: `local-users`, `local-admins`, `ssh-pubkeys`
- Services: `kerberos-services`, `docker-server`
- Deploy: `deploy.enable`, `deploy.ssh-options`
- Security: `hardened`, `encrypted-filesystems`

**Use case**: Central inventory of all infrastructure hosts. Each host references itself and can query other hosts.

#### `sites.nix` - Physical Site Definitions
Geographic or logical site groupings.

**Options**: `fudo.sites.<site>.*`
- Network: `network`, `gateway`, `local-gateway`
- Deploy: `deploy-pubkeys`
- Nexus: Public/private/tailscale domains

**Use case**: Group hosts by physical location or network segment.

#### `zones.nix` - DNS Zone Definitions
DNS zone data used by authoritative DNS servers.

**Options**: `fudo.zones.<zone>.*`
- Hosts: `hosts` (with IPv4/IPv6/description/SSHFP)
- Records: `nameservers`, `mx`, `srv-records`, `aliases`
- DNSSEC: `gssapi-realm`, `dmarc-report-address`
- Custom: `verbatim-dns-records`, `subdomains`

**Use case**: Define DNS zones that get rendered to zonefiles by authoritative-dns flake.

---

### Authentication & Authorization

#### `authentication.nix` - LDAP Integration
Configure system to authenticate users via LDAP.

**Options**: `fudo.authentication.*`
- LDAP connection: `ldap-url`, `ssl-ca-certificate`, `base`
- Credentials: `bind-passwd-file`

**Use case**: Connect hosts to centralized LDAP user directory.

#### `auth/kerberos/default.nix` - Kerberos Client
Heimdal Kerberos client configuration.

**Options**: Configures `security.krb5` automatically from domain settings.

**Use case**: Enable Kerberos SSO for realm members.

#### `auth/kerberos/kdc.nix` - Kerberos KDC
Run a Kerberos Key Distribution Center.

**Options**: `fudo.auth.kerberos.kdc.*`
- `enable`, `realm`, `admin-password-file`
- `state-directory`, `kdc-address`

**Use case**: Central authentication server for realm.

---

### Secrets Management

#### `secrets.nix` - Age-Based Secret Management
Encrypt secrets for specific hosts using age and their public keys.

**Options**: `fudo.secrets.*`
- `host-secrets.<hostname>.<secret-name>`: Define secrets per host
  - `source-file`: Plaintext secret (at build time)
  - `target-file`: Where to decrypt on host
  - `user`, `group`, `permissions`
- `files.*`: Pre-defined secrets structure (DNS keys, SSH keys, etc.)

**Use case**: Manage secrets that are encrypted at build time and decrypted on target hosts.

**Extraction candidate**: Generic age-based secret management (HIGH priority).

---

### Service Modules

#### `nexus.nix` - Nexus DDNS Configuration
Define domains served by Nexus dynamic DNS system.

**Options**: `fudo.nexus.domains.<domain>.*`
- `server`: Primary Nexus server hostname
- `secondary-dns-servers`: Secondary DNS for the domain
- `gssapi-realm`: Kerberos realm (optional)
- `trusted-networks`: Networks allowed AXFR
- `records`: Static DNS records

**Use case**: Configure Nexus domains. Works with separate nexus flake for client/server/DNS implementations.

**Status**: KEEP - actively used, good separation from nexus flake.

#### `webmail.nix` - Rainloop Webmail
PHP-based webmail interface using Rainloop Community.

**Options**: `fudo.webmail.*`
- `sites.<hostname>`: Per-site configuration
  - `title`, `mail-server`, `domain`, `favicon`
  - `edit-mode`, `layout-mode`, `theme`
  - `database`: PostgreSQL for contacts (optional)

**Use case**: Provide web-based email access. Currently serving 3 webmail domains.

**Extraction candidate**: Could be separate flake (MEDIUM priority).

#### `postgres.nix` - PostgreSQL Database Server
PostgreSQL with user/database management.

**Options**: `fudo.postgres.*`
- `enable`, `listen-addresses`, `port`
- `users.<name>`: Create users with passwords
- `databases.<name>`: Create databases with access control
- `monitoring`: Prometheus metrics

**Use case**: Centralized database server.

**Extraction candidate**: Generic PostgreSQL module (MEDIUM priority).

#### `git.nix` - Git Server (Gitea)
Gitea instance with PostgreSQL backend.

**Options**: `fudo.git.*`
- `enable`, `domain`, `listen-port`
- `database`: PostgreSQL connection
- `state-directory`

**Use case**: Self-hosted Git repositories.

#### `slynk.nix` - Common Lisp REPL Server
Slynk (Swank successor) for remote Lisp development.

**Options**: `fudo.slynk.*`
- `enable`, `port`, `interface`

**Use case**: Remote Common Lisp development/debugging.

**Extraction candidate**: Lisp development tools (MEDIUM priority).

#### `minecraft-server.nix` - Minecraft Server
Java-based Minecraft server.

**Options**: `fudo.minecraft-server.*`
- `enable`, `server-properties`, `eula`
- `state-directory`, `package`

**Use case**: Personal Minecraft server.

#### `minecraft-server-multi.nix` - Multi-Instance Minecraft
Run multiple Minecraft server instances from one host.

**Use case**: Host several Minecraft worlds/servers side by side.

#### `minecraft-clj.nix` - Clojure Minecraft Tools
Clojure-based Minecraft utilities.

**Use case**: Custom Minecraft automation.

---

### Monitoring & Observability

#### `prometheus.nix` - Metrics Collection
Prometheus time-series database with scraper configuration.

**Options**: `fudo.metrics.prometheus.*`
- `scrapers`: Define targets via DNS-SD
- `listen-address`, `storage-retention`

**Use case**: Collect metrics from infrastructure.

**Extraction candidate**: Prometheus + Grafana stack (MEDIUM priority).

#### `grafana.nix` - Metrics Visualization
Grafana with OAuth support and datasources.

**Options**: `fudo.metrics.grafana.*`
- `oauth`: Authentik SSO integration
- `datasources`: Prometheus, Loki
- `listen-address`, `listen-port`
- `database`: PostgreSQL backend

**Use case**: Metrics dashboards and visualization.

#### `node-exporter.nix` - System Metrics
Export system metrics for Prometheus.

**Options**: `fudo.metrics.node-exporter.*`
- `enable`, `listen-address`, `listen-port`

**Use case**: Expose host metrics.

---

### Networking Services

#### `secure-dns-proxy.nix` - DNS-over-HTTPS/TLS Proxy
DNS proxy supporting DoH and DoT.

**Options**: `fudo.secure-dns-proxy.*`
- `enable`, `port`, `listen-ips`
- `upstream-dns`: DoH/DoT endpoints
- `bootstrap-dns`: Initial resolver

**Use case**: Encrypted DNS for privacy.

#### `adguard-dns-proxy.nix` - DNS Filtering Proxy
DNS-based ad/tracker blocking.

**Options**: `fudo.adguard-dns-proxy.*`
- DNS: `listen-port`, `reverse-dns`
- HTTP: Web UI configuration
- Filtering: Blocklists and rules

**Use case**: Network-wide ad blocking.

---

### Infrastructure Utilities

#### `acme-certs.nix` - Let's Encrypt Automation
Centralized ACME certificate management.

**Options**: `fudo.acme-certs.*`
- `enable`, `certs.<domain>`
- `state-directory`, `redirect-target`

**Use case**: Automated TLS certificate provisioning.

**Extraction candidate**: Generic ACME automation (HIGH priority).

#### `deploy.nix` - Deployment Key Management
Inject deployment SSH keys into root account.

**Use case**: Enable deploy-rs deployments.

#### `ssh.nix` - SSH / fail2ban Integration
Populates `programs.ssh.knownHosts` from the `fudo.hosts` inventory and wires
fail2ban (IP whitelisting via `fudo.ssh.whitelistIPs`, stricter retry limits on
hardened hosts).

**Options**: `fudo.ssh.whitelistIPs`

**Use case**: Fleet-wide known-hosts and brute-force protection driven by the
host inventory.

#### `host-filesystems.nix` - Encrypted Filesystem Management
LUKS-encrypted filesystem mounting with key management.

**Options**: Configure via host type definition (`encrypted-filesystems`).

**Use case**: Automatic decryption and mounting of encrypted storage.

#### `system.nix` - Systemd Service Abstractions
Helper for defining systemd services.

**Options**: `fudo.system.services.<name>`
- Simplified service definitions
- Sandboxing presets
- Common patterns

**Use case**: Reduce boilerplate in service definitions.

**Extraction candidate**: Systemd helpers (HIGH priority).

#### `system-networking.nix` - Network Configuration
Network setup based on host configuration.

**Use case**: Automatic network configuration from host inventory.

#### `users.nix` - User Management
Create users and groups from configuration.

**Use case**: Centralized user management across hosts.

#### `password.nix` - Password Utilities
Password hashing and generation.

**Use case**: Generate stable passwords from seeds.

#### `wireless-networks.nix` - WiFi Configuration
Manage WiFi network configurations.

**Options**: `fudo.wireless-networks.<ssid>`

**Use case**: Laptop WiFi setup.

#### `global.nix` - Global Configuration Options
Top-level configuration flags.

**Use case**: Feature flags and global settings.

---

### Informis Namespace

Personal/experimental modules (probably won't extract).

#### `informis/chute.nix` - Cryptocurrency Parachute
Automated crypto sell-off when prices drop.

**Options**: `informis.chute.*`
- `stages.<name>.currencies`: Track currencies
- Stop-loss automation
- Jabber notifications

**Use case**: Personal finance automation experiment.

#### `informis/cl-gemini.nix` - Gemini Protocol Server
Common Lisp Gemini protocol server.

**Options**: `informis.cl-gemini.*`
- `feeds`: RSS-like feeds for Gemini

**Use case**: Personal Gemini capsule.

---

## Utility Libraries

Pure functions with no NixOS module dependencies. **Excellent extraction candidates.**

### `lib/ip.nix` - IP Address Utilities
**Functions**:
- `networkMinIp`, `networkMaxIp`: CIDR range boundaries
- `networkBase`: Extract network base from CIDR
- `maskFromV32Network`: Get subnet mask from CIDR
- `reverseIpv4`: Reverse IP for PTR records
- `ipv4ToInt`, `intToIpv4`: Conversions

**Extraction priority**: HIGH - Pure utilities, widely useful.

### `lib/network.nix` - Network Utilities
**Functions**:
- `generate-mac-address`: Deterministic MAC from hostname+interface

**Extraction priority**: HIGH - Generic utility.

### `lib/lisp.nix` - Common Lisp Utilities
**Functions**:
- `gather-dependencies`: Collect transitive dependencies
- `lisp-source-registry`: Build CL_SOURCE_REGISTRY path

**Extraction priority**: MEDIUM - Useful for Lisp projects.

### `lib/passwd.nix` - Password Utilities
**Functions**:
- `stablerandom-passwd-file`: Generate stable passwords from seed
- `hash-password`: bcrypt hashing

**Extraction priority**: HIGH - Security utilities.

### `lib/text.nix` - Text Manipulation
**Functions**:
- String processing utilities

**Extraction priority**: LOW - Check if duplicates nixpkgs.lib.

### `lib/filesystem.nix` - Filesystem Utilities
**Functions**:
- File operation helpers

**Extraction priority**: LOW - Check if duplicates nixpkgs.lib.

---

## Type Definitions

Shared configuration schemas.

### `types/host.nix` - Host Configuration Schema
Complete host attribute definition.

### `types/user.nix` - User/Group Schemas
User and group configuration structures.

### `types/network-host.nix` - Network Host Attributes
IP addresses, MAC, SSH fingerprints, description.

### `types/zone-definition.nix` - DNS Zone Structure
Recursive zone definition with hosts, records, subdomains.

---

## Usage

### As a Flake

```nix
{
  inputs.fudo-nix-lib.url = "github:fudoniten/fudo-nix-lib";
  
  outputs = { nixpkgs, fudo-nix-lib, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        fudo-nix-lib.nixosModules.default  # Adds all fudo.* options
        {
          instance.hostname = "myhost";
          fudo.hosts.myhost = { ... };
        }
      ];
    };
  };
}
```

### Accessing Utilities

```nix
{ pkgs, ... }:
{
  # IP utilities
  pkgs.lib.ip.networkMinIp "10.0.0.0/24"  # => "10.0.0.1"
  
  # Network utilities
  pkgs.lib.network.generate-mac-address "myhost" "eth0"
  
  # Password utilities
  pkgs.lib.passwd.stablerandom-passwd-file "my-service" "seed123"
  
  # Lisp utilities
  pkgs.lib.lisp.lisp-source-registry myLispPackage
}
```

---

## Extraction Strategy

See [TODO.md](./TODO.md) for detailed removal plan.

### Phase 1: Remove Obsolete Code (~1,850 lines)
After testing mail configuration:
1. Remove mail stack modules
2. Remove VPN module
3. Remove local-network module
4. Remove common.nix placeholder

### Phase 2: Extract High-Value Utilities
Priority order:
1. **Secrets management** - Generic, secure, useful
2. **IP/Network utilities** - Pure functions, widely applicable
3. **ACME certificates** - Generic TLS automation
4. **System helpers** - Reduce systemd boilerplate

### Phase 3: Extract Service Modules
As needed:
- PostgreSQL module
- Monitoring stack (Prometheus + Grafana)
- Webmail server

### Phase 4: Keep Infrastructure Core
These are specific to personal infrastructure:
- domains/hosts/sites/zones model
- Nexus integration
- Informis namespace

---

## Development Notes

### Adding New Modules

1. Create module in appropriate directory
2. Add import to `lib/fudo/default.nix`
3. Define options under `fudo.*` namespace
4. Document in this README

### Testing Changes

```bash
# Syntax check
nix-instantiate --parse lib/fudo/mymodule.nix

# Build test configuration
nixos-rebuild build --flake .#hostname

# Check option docs
nixos-option fudo.mymodule
```

### Code Quality Guidelines

- Avoid TODOs/FIXMEs in production code (document in TODO.md instead)
- Prefer pure functions in lib/ over stateful modules
- Keep infrastructure logic (fudo.*) separate from utilities (lib.*)
- Document extraction candidates as you identify them

---

## Related Projects

- **nixos-config** (`/net/projects/niten/nixos-config`) - Consuming configuration
- **mail-server** (`github:fudoniten/nix-mail-server`) - Replacement for mail stack
- **authoritative-dns** (`github:fudoniten/authoritative-dns-module`) - DNS server
- **nexus** (`github:fudoniten/nexus`) - Dynamic DNS system
- Various container modules (authentik, nextcloud, lemmy, etc.)

---

## Migration Path

```
Current State (fudo-nix-lib monorepo)
  ↓
Remove obsolete code (~1,850 lines)
  ↓
Extract utilities to fudo-utils flake
  ↓
Extract secrets management to fudo-secrets-v2 flake
  ↓
Extract service modules as needed
  ↓
Final State: Small infrastructure core + many focused flakes
```

**Target**: ~2,000 lines of infrastructure-specific code + separate utility flakes.

**Timeline**: Incremental as time permits, following TODO.md priorities.
