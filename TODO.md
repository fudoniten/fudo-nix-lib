# Cleanup TODO

Inventory of what is left in fudo-nix-lib, who still uses it, and where each
piece should go when the repo is broken up. Last audited 2026-11-02 against
nixos-config `26.05-aegis`, fudo-entities, fudo-nix-home, sea-build, and every
flake nixos-config takes as an input that is public (aegis, nexus,
nix-mail-server, matrix-module, authoritative-dns-module, kubernetes-cluster,
the `*-container` flakes). Not checked: the private `fudo-secrets` flake
(`path:/secrets`), `paris-container` and `summarizer`.

"Used" below means a consumer sets the module's options or reads its config,
found by searching those repos. The removals were checked by evaluating the
module set against the real fudo-entities data, but only the full eval on
forge covers every host.

## Removed (2026-11)

| What | Why |
|---|---|
| `lib/fudo/postgres.nix` (`fudo.postgresql`) | Shared site-wide servers retired (nixos-config #216). Its one remaining user, the nexus server's database on legatus, now carries a copy in nixos-config as `fudo.services.postgresql`. |
| `lib/fudo/git.nix` (`fudo.git`) | No consumer. Gitea runs from nixos-config's `gitea-container.nix`. |
| `lib/fudo/grafana.nix` (`fudo.metrics.grafana`) | No consumer. Grafana runs in Kubernetes. |
| `lib/fudo/minecraft-clj.nix` | No consumer. |
| `lib/fudo/authentication.nix` (`fudo.authentication`, LDAP NSS) | No consumer. |
| `lib/fudo/global.nix` | Empty module. |
| `lib/informis/` (`informis.chute`, `informis.cl-gemini`) | No consumer. `cl-gemini` is only a commented-out block on legatus; `chute` went with informis.land. |
| `lib/lib/lisp.nix` (`pkgs.lib.lisp`) | Only `cl-gemini` used it. |
| `lib/lib/text.nix` (`pkgs.lib.text`) | No callers. |
| Inventory schema (`instance.nix`, `domains`, `hosts`, `sites`, `zones`, `nebula`, `nexus`, `users`, `types/`) | Moved, not deleted: the inventory schema to fudo-entities `schema/`; `instance.*` and the users schema to nixos-config; the per-host behaviour in `hosts.nix`/`sites.nix` to nixos-config `system/inventory.nix`. |
| `lib/fudo/acme-certs.nix` (`fudo.acme`) | Nothing set `host-domains`. Its unconditional `allowedTCPPorts = [ 80 443 ]` on every host is replaced in nixos-config by opening them wherever nginx runs (`system/common.nix`). |
| `lib/fudo/password.nix` (`fudo.password`) | No file generators. Nexus waited on its `fudo-passwords.target` only in the legacy build-seed password path, which nixos-config removed. |
| `fudo.domains.<d>.postgresql-server`, `chat-server`, `wireguard.*` | Never read. `postgresql-server` was dropped from fudo-entities in #34; `wireguard` went with `vpn.nix`. |

Earlier removals (mail stack, `vpn.nix`, `hosts/local-network.nix`,
`common.nix`) are in git history.

## Dead, but not a straight delete

- **`domains.<d>.metrics.grafana-host`**: nothing reads it since Grafana moved
  to Kubernetes, but it has no default and fudo-entities sets it for
  `sea.fudo.org` and `fudo.org`. Give it a default (or drop it from
  fudo-entities first), then remove it.
- **`ssh.nix`**: `fudo.ssh.whitelistIPs` is never set, but the module sets
  fail2ban's ignore list and `programs.ssh.knownHosts` on every host, so it is
  live. Only the option is dead.

## Still live

| Module | Used by | Where it should go |
|---|---|---|
| `secrets.nix` (`fudo.secrets`) | ~22 files in nixos-config, plus nexus.nix | Goes away with the fudo-secrets → Aegis migration, not extracted. |
| `auth/kerberos/` (client and KDC) | `services/fudo-auth.nix`, `services/kdc-aegis.nix` | Next to the Aegis KDC (`aegis.nixosModules.kdc`) or into nixos-config `services/`. |
| `adguard-dns-proxy.nix` | `services/local-network/recursor.nix`, sea/burg domain configs | nixos-config `services/local-network/`, its only user. |
| `secure-dns-proxy.nix` | legatus | nixos-config, or merge with adguard into one DNS-proxy flake. |
| `system.nix` (`fudo.system.services`) | Only `secure-dns-proxy.nix`. Also defines `fudo-init.target`. | Inline into `secure-dns-proxy.nix` and delete. |
| `system-networking.nix` (`fudo.system.hostfile-entries`) | `services/local-network/gateway.nix`, `profiles/host/ssh.nix` | nixos-config. |
| `prometheus.nix`, `node-exporter.nix` (`fudo.metrics.*`) | nixos-config `services/metrics.nix`, `profiles/common.nix` | nixos-config `services/metrics.nix`, which is already their only driver. |
| `webmail.nix` + `include/rainloop.nix` | fudo.org (`webmail.fudo.org` on france) | Retire if webmail is no longer wanted; otherwise nixos-config or the mail-server flake. |
| `minecraft-server.nix` (`fudo.minecraft-server`) | nostromo | Fold into `minecraft-server-multi.nix` and move both to a minecraft flake or nixos-config. |
| `minecraft-server-multi.nix` (`fudo.services.minecraft.server`) | arx | Same as above. |
| `slynk.nix` | atom, system7 | fudo-nix-home (it's a dev tool) or nixos-config. |
| `wireless-networks.nix` | `profiles/laptop.nix`, `system/wireless-networks.nix` | nixos-config. |
| `deploy.nix` | Every host: root's `authorized_keys` from each site's `deploy-pubkeys` (forge deploys) | nixos-config `profiles/host/deploy-user.nix`. |
| `host-filesystems.nix` | lambda, nostromo (`encrypted-filesystems`) | nixos-config. |

## Utility functions (`pkgs.lib.*`)

| Library | Called from outside this repo | Not called anywhere |
|---|---|---|
| `fs` | `import-by-basename` (fudo-entities) | `matches-ext`, `get-ext`, `hostname-from-file`, `ext-files`, `basename-to-file-map`, `list-nix-files` |
| `ip` | `maskFromV32Network`, `networkMinIp`, `networkMaxIp`, `ipv4OnNetwork`, `getNetworkMask`, `getNetworkBase` (nixos-config, authoritative-dns-module) | `networkMaxButOneIp`, `reverseIpv4`, plus helpers only used internally |
| `network` | `host-ipv4`, `host-ipv6`, `generate-mac-address` (nixos-config) | `host-ips`, `site-gateway` |
| `passwd` | `stablerandom-passwd-file` (nixos-config, nix-mail-server, authentik and nextcloud containers, adguard) | `hash-ldap-passwd`, `bcrypt-passwd`, `generate-random-passwd`, `random-passwd-file` |

These are pure and have no module dependencies, so they can move as one small
public flake. The `passwd` helpers derive passwords from `build-seed` and go
away with the Aegis migration.

## Suggested order for breaking the repo up

1. Move each single-consumer service module into nixos-config `services/`
   (adguard, secure-dns-proxy with `system.nix` inlined, prometheus and
   node-exporter, wireless-networks, host-filesystems, deploy,
   system-networking). Each is a move plus an option rename, the same
   pattern as postgres.
2. Settle webmail (retire or move), minecraft (merge the two modules) and
   slynk.
3. Split out the pure utilities as a flake, keeping only the functions that
   have callers.
4. ~~Move the inventory schema out~~ (done 2026-11: into fudo-entities).
5. Delete `secrets.nix` and the `passwd` helpers when the
   Aegis migration finishes.

## Code-quality notes on live modules

- `webmail.nix`: `# TODO: make this a fudo service` on its systemd services.
