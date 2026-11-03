# fudo-nix-lib

Personal NixOS module and utility library for managing infrastructure across domains, sites, and hosts.

**Status**: Monorepo in process of being decomposed into reusable flakes.

**Audience**: Personal reference for infrastructure management and extraction planning.

---

## Quick Stats

- **~4,000 lines** of Nix code
- **15 modules** in the `fudo.*` namespace (the `informis.*` namespace is gone)
- **4 utility libraries** (pure functions)
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
│   └── *.nix          # Service/infra modules (prometheus, webmail, minecraft, …)
├── lib/               # Utility libraries (pure functions)
└── default.nix        # Module aggregator

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
- **PostgreSQL (`fudo.postgresql`)** – the shared site-wide servers were
  retired; the one remaining user (the nexus server's database on legatus)
  carries the module in nixos-config as `fudo.services.postgresql`.
- **Unused service modules** – `git.nix` (Gitea), `grafana.nix` (Grafana now
  runs in Kubernetes), `minecraft-clj.nix`, `authentication.nix` (LDAP NSS),
  the empty `global.nix`, and the whole `informis/` namespace (`chute`,
  `cl-gemini`). None had a consumer.
- **`acme-certs.nix` and `password.nix`** – `fudo.acme` and
  `fudo.password.file-generator` had no users. acme-certs also opened 80/443 on
  every host; nixos-config now opens them wherever nginx runs. Nexus's
  dependency on `fudo-passwords.target` went with its legacy password fallback.
- **Unused utilities** – `lib/lisp.nix` (only `cl-gemini` used it) and
  `lib/text.nix` (no callers), so `pkgs.lib.lisp` and `pkgs.lib.text` are gone.
- **Unused domain options** – `fudo.domains.<d>.postgresql-server`,
  `chat-server` and `wireguard.*`.

---

## Active Modules

### Core Infrastructure

The inventory model (`fudo.domains`, `fudo.hosts`, `fudo.sites`,
`fudo.zones`, `fudo.nebula`, `fudo.nexus` and the host/zone types) moved to
**fudo-entities** (`schema/`) in 2026-11, next to the data that fills it.
`instance.*` and the `fudo.users`/`groups`/`system-users` schema moved to
**nixos-config** (`system/instance.nix`, `identity/schema.nix`), and the
per-host behaviour `hosts.nix`/`sites.nix` carried went to nixos-config's
`system/inventory.nix`. The modules below still *read* that model.

---

### Authentication & Authorization

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

#### `webmail.nix` - Rainloop Webmail
PHP-based webmail interface using Rainloop Community.

**Options**: `fudo.webmail.*`
- `sites.<hostname>`: Per-site configuration
  - `title`, `mail-server`, `domain`, `favicon`
  - `edit-mode`, `layout-mode`, `theme`
  - `database`: PostgreSQL for contacts (optional)

**Use case**: Provide web-based email access. Currently serving 3 webmail domains.

**Extraction candidate**: Could be separate flake (MEDIUM priority).

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

### Monitoring & Observability

#### `prometheus.nix` - Metrics Collection
Prometheus time-series database with scraper configuration.

**Options**: `fudo.metrics.prometheus.*`
- `scrapers`: Define targets via DNS-SD
- `listen-address`, `storage-retention`

**Use case**: Collect metrics from infrastructure.

**Extraction candidate**: Prometheus stack (MEDIUM priority).

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

#### `wireless-networks.nix` - WiFi Configuration
Manage WiFi network configurations.

**Options**: `fudo.wireless-networks.<ssid>`

**Use case**: Laptop WiFi setup.

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

### `lib/passwd.nix` - Password Utilities
**Functions**:
- `stablerandom-passwd-file`: Generate stable passwords from seed
- `hash-password`: bcrypt hashing

**Extraction priority**: HIGH - Security utilities.

### `lib/filesystem.nix` - Filesystem Utilities
**Functions**:
- File operation helpers

**Extraction priority**: LOW - Check if duplicates nixpkgs.lib.

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

}
```

---

## Extraction Strategy

[TODO.md](./TODO.md) has the current inventory: what is still live, who uses
it, what is dead but needs a step before it can go, and where each piece should go when the
repo is broken up.

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
