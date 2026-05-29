# Cleanup TODO

This document tracks obsolete modules and code that should be removed from fudo-nix-lib. These items have been verified as unused or superseded by separate flakes.

## High Priority - Verified Obsolete

### Mail Modules (Replaced by `mail-server` flake)

**Status**: Obsolete - replaced by github:fudoniten/nix-mail-server

**Evidence**: 
- nixos-config imports the new mail-server flake which provides `fudo.mail.*` options
- Old modules provide `fudo.mail-server.*` options (different namespace)
- Only lingering reference is in `nixos-config/config/aliases.nix` using wrong option path (to be fixed)

**Prerequisites**: 
1. ✅ Fix `nixos-config/config/aliases.nix` to use `fudo.mail.aliases.alias-users`
2. ✅ Test mail configuration works correctly
3. ⏸️ Remove modules after confirmation

**Modules to remove**:
- [ ] `lib/fudo/mail.nix` (~200 lines) - Main mail server orchestration
- [ ] `lib/fudo/mail-container.nix` (~400 lines) - Containerized mail setup
- [ ] `lib/fudo/mail/` - Entire mail subdirectory:
  - [ ] `mail/postfix.nix` (~300 lines)
  - [ ] `mail/dovecot.nix` (~250 lines)
  - [ ] `mail/rspamd.nix` (~150 lines)
  - [ ] `mail/clamav.nix` (~100 lines)
  - [ ] `mail/dkim.nix` (~80 lines)
  - [ ] `mail/dovecot/imap_sieve/report-ham.sieve`
  - [ ] `mail/dovecot/imap_sieve/report-spam.sieve`
  - [ ] `mail/dovecot/pipe_bin/sa-learn-ham.sh`
  - [ ] `mail/dovecot/pipe_bin/sa-learn-spam.sh`

**Update imports**:
- [ ] `lib/fudo/default.nix` - Remove `./mail.nix` and `./mail-container.nix` imports

**Estimated impact**: ~1,500 lines removed

---

### VPN Module (Never used)

**Status**: Completely unused

**Evidence**: No references to `fudo.vpn` anywhere in nixos-config

**Modules to remove**:
- [x] `lib/fudo/vpn.nix` (~200 lines) - WireGuard VPN configuration

**Update imports**:
- [x] `lib/fudo/default.nix` - Remove `./vpn.nix` import

**Estimated impact**: ~200 lines removed

---

### Local Network Module (Replaced by nixos-config implementation)

**Status**: Obsolete (file itself says "THROW THIS AWAY, NOT USED")

**Evidence**:
- File header comment: "# THROW THIS AWAY, NOT USED"
- FIXME comment on line 9: "# FIXME: this isn't used, is it?"
- No references to `fudo.hosts.local-network` in nixos-config
- Superseded by `nixos-config/config/service/local-network/`

**Modules to remove**:
- [ ] `lib/fudo/hosts/local-network.nix` (~144 lines)
- [ ] `lib/fudo/hosts/` directory (if empty after removal)

**Estimated impact**: ~144 lines removed

---

## Low Priority - Cleanup Opportunities

### Empty Module

**Status**: Empty placeholder module with no functionality

**Modules to remove**:
- [ ] `lib/fudo/common.nix` (4 lines) - Empty module with just comments and empty attribute set

**Update imports**:
- [ ] `lib/fudo/default.nix` - Remove `./common.nix` import

**Estimated impact**: Minimal, but reduces clutter

---

### Code Quality Improvements

These items have TODOs/FIXMEs but are actively used. Address when time permits:

**lib/fudo/webmail.nix:345**
```nix
# TODO: make this a fudo service
systemd.services = { ... }
```
→ Consider refactoring to use fudo.system.services abstraction

**lib/fudo/grafana.nix:217**
```nix
# TODO: create system user as necessary
```
→ Ensure user creation is handled properly

**lib/fudo/mail/postfix.nix:121**
```nix
# TODO: enable!
```
→ Review what needs to be enabled (may be obsolete with mail-server flake)

**lib/fudo/acme-certs.nix:140**
```nix
# THIS IS A HACK. Getting redundant paths. So if {domain} is configured
```
→ Review certificate path handling logic

---

## Summary Statistics

**Immediate cleanup potential**:
- ~1,850 lines of obsolete code
- 3 obsolete module directories
- 1 empty placeholder file

**Active modules remaining**: ~30 modules (~4,000 lines)

**Module categories to preserve**:
- ✅ Core infrastructure (domains, hosts, sites, zones, instance, types)
- ✅ Authentication (Kerberos, LDAP)
- ✅ Secrets management
- ✅ Monitoring (Prometheus, Grafana, node-exporter)
- ✅ Services (PostgreSQL, Git, Slynk, Minecraft, Webmail)
- ✅ Networking (Nexus, secure-dns-proxy, wireless)
- ✅ System utilities (acme-certs, deploy, system, users)
- ✅ Utility libraries (ip, network, lisp, passwd, text, filesystem)
- ✅ Informis namespace (chute, cl-gemini)

---

## Execution Plan

1. **Phase 1**: Fix nixos-config mail configuration (safe, testable)
   - Update aliases.nix option path
   - Remove defensive mail-server.enable
   - Test thoroughly

2. **Phase 2**: Remove obsolete modules from fudo-nix-lib
   - Remove mail modules
   - Remove vpn module
   - Remove local-network module
   - Remove common.nix
   - Update all import statements

3. **Phase 3**: Verify and document
   - Verify no broken references
   - Update README.md with current module list
   - Consider extraction candidates for separate flakes

---

## Future Extraction Candidates

These modules are good candidates for extraction into separate, reusable flakes:

**High reusability**:
- secrets.nix - Generic age-based secret management
- lib/ip.nix, lib/network.nix, lib/passwd.nix - Pure utility functions
- acme-certs.nix - Let's Encrypt automation
- system.nix - Systemd service helpers

**Medium reusability** (need minor cleanup):
- postgres.nix - Database management
- prometheus.nix / grafana.nix - Monitoring stack
- node-exporter.nix - Metrics exporter
- webmail.nix - Rainloop webmail server
- auth/kerberos - Kerberos setup

**Fudo-specific** (keep here):
- domains.nix, hosts.nix, sites.nix - Infrastructure model
- zones.nix - DNS zone definitions
- nexus.nix - Nexus DDNS integration
- informis/* - Personal experiments
