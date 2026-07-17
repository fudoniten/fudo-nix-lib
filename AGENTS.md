# AGENTS.md — fudo-nix-lib

Guidance for AI agents (and humans) working in this repository. Read this first,
then dig into the specific module you need. [`README.md`](./README.md) has a
detailed per-module catalogue and an extraction/migration plan;
[`TODO.md`](./TODO.md) tracks cleanup. This file focuses on *how the code is
organized and why*.

## What this repo is

A **reusable NixOS module + utility library** in the `fudo.*` namespace. It is a
pure library flake: it defines *options and helpers* but is not itself a host
config. It is consumed by `nixos-config` (as the `fudo-lib` input) and, in
principle, by any flake that wants the `fudo.*` modules or the `pkgs.lib.*`
utility functions.

**Status:** legacy, and **being deliberately shrunk**. This grab-bag got
unwieldy, and the maintainer is decomposing it into smaller, reusable,
special-purpose flakes. The preferred direction is to pull concerns *out* into
focused flakes, not to add more here. Several modules are already extraction
candidates or pending removal — see `TODO.md` before adding to or refactoring
them. Adding a brand-new concern to this repo should be the exception; default
to a new focused flake instead.

## The three-repo family

| Repo | Role | Namespace |
|------|------|-----------|
| **fudo-nix-lib** (here) | Reusable infra modules + pure utilities + shared types | `fudo.*`, `informis.*`, `pkgs.lib.*` |
| **fudo-nix-home** | Per-user Home Manager configs + custom HM modules | `fudo.home-manager.*` |
| **nixos-config** | Top-level flake; assembles per-host `nixosConfigurations` and consumes both libraries | (consumer) |

This repo sits at the bottom of the stack: it depends on none of the others,
and both of the others (directly or indirectly) depend on it. A change here can
ripple into every host, so when you *do* touch it, prefer additive, opt-in
options over changing existing behavior — but prefer extracting a concern into
its own flake over adding to this one at all (see Status above).

Host/site/domain *data* is **not** here — it lives in the private
`fudo-entities` flake. This repo defines the *schemas* (`lib/types/`) and the
*modules* that consume such data; the data itself lives elsewhere.

## Flake outputs (the public surface)

From `flake.nix`:

- `nixosModules.default` (alias `fudo`) → `module.nix`, which imports `lib/`.
  This is what gives a system all the `fudo.*` (and `informis.*`) options.
- `nixosModules.lib` → a tiny module that just registers the overlay.
- `overlays.default` (alias `lib`) → `overlay.nix`, which merges the utility
  functions into `pkgs.lib` (so consumers get `pkgs.lib.ip.*`, `pkgs.lib.passwd.*`,
  etc.).
- `lib` → `lib.nix`, the raw utility function set (needs a `pkgs`).

The two delivery mechanisms to keep straight:
- **Modules** (`fudo.*` options) come in via `nixosModules.default`.
- **Utilities** (`pkgs.lib.*` pure functions) come in via `overlays.default`.

## Directory map

```
flake.nix          # outputs: nixosModules, overlays, lib
module.nix         # NixOS module entry → imports ./lib
lib.nix            # utility function exports (→ pkgs.lib.*)
overlay.nix        # nixpkgs overlay that injects lib.nix into pkgs.lib
lib/
├── default.nix    # module aggregator: imports instance.nix, fudo/, informis/
├── instance.nix   # per-host identity/context (instance.* options)
├── fudo/          # the infrastructure modules (fudo.* namespace)
│   ├── default.nix    # imports every module in this dir
│   ├── auth/          # Kerberos client + KDC
│   ├── include/       # included/shared config fragments
│   ├── domains.nix hosts.nix sites.nix zones.nix   # the core inventory model
│   ├── secrets.nix    # age-based secret management
│   ├── postgres.nix git.nix grafana.nix prometheus.nix …   # services
│   └── …
├── informis/      # personal/experimental modules (informis.* — unlikely to extract)
├── lib/           # PURE utility functions (no module deps)
│   ├── ip.nix network.nix passwd.nix lisp.nix text.nix filesystem.nix
└── types/         # shared configuration schemas
    └── host.nix user.nix network-host.nix zone-definition.nix
```

## The core model: instance / domains / hosts / sites / zones

The heart of the library is a small set of modules that model infrastructure at
increasing scope. Most other modules read from these:

- **`instance.nix`** — *this* host's identity (`instance.hostname`,
  `local-domain`, `local-networks`, `build-seed`, …). Every other module adapts
  to the current host through `instance.*`.
- **`fudo.domains.<domain>`** — domain-wide services and policy (auth realms,
  mail/DNS servers, trusted networks).
- **`fudo.hosts.<hostname>`** — the host inventory: identity, network, access,
  services, deploy flags. Hosts can query each other.
- **`fudo.sites.<site>`** — physical/logical site grouping (network, gateway).
- **`fudo.zones.<zone>`** — DNS zone data, rendered to zonefiles by the
  authoritative-dns flake.

The `types/` schemas define the shape of these attribute sets.

## Key patterns & conventions

- **Two clean layers.** Keep infra logic (`fudo.*` / `informis.*` modules under
  `lib/fudo` and `lib/informis`) separate from pure utilities (`lib/lib`). A
  function in `lib/lib` must not depend on NixOS module machinery — that's what
  makes it an extraction candidate.
- **Register new modules** by adding the file under `lib/fudo/` and adding it to
  `lib/fudo/default.nix`'s imports. New pure utilities go in `lib/lib/<name>.nix`
  and get exported from `lib.nix`.
- **Options live under `fudo.<module>.*`** (or `informis.*`). Follow the existing
  option-declaration style (typed `mkOption`, `with lib;`).
- **No TODOs/FIXMEs in module code** — record cleanup in `TODO.md` instead
  (house rule from README).
- **`informis.*`** is the personal/experimental namespace (chute, cl-gemini) and
  is not intended for extraction.

## Working on this repo

```bash
# Parse-check a module
nix-instantiate --parse lib/fudo/<module>.nix

# Confirm the module set / overlay evaluate
nix eval .#nixosModules.default --apply builtins.typeOf
nix eval .#overlays.default --apply builtins.typeOf

# Utilities are pure — you can exercise them via a pkgs set, e.g.
#   pkgs.lib.ip.networkMinIp "10.0.0.0/24"
```

Because this is a library, there's no host to `nixos-rebuild`; validate by
parsing, by `nix eval` on the outputs, and — for real integration — by building
a host in `nixos-config` that pins your branch.

## Branch & release convention

Release branches are named for the NixOS release (e.g. `25.11`, `26.05`).
`nixos-config` pins a matching release of this flake (`fudo-lib.url =
github:fudoniten/fudo-nix-lib/<release>`), so an option rename here must be
coordinated with the consuming release branch. Do current work on the feature
branch you were given.

## Gotchas

- The `README.md` module catalogue can lag the tree (e.g. it still lists a mail
  stack, `vpn.nix`, `local-network`, and `common.nix` under "pending removal" —
  several are already gone). Trust `lib/fudo/default.nix` for the authoritative
  list of what's actually imported.
- Changes here are high-blast-radius (every host imports `nixosModules.default`).
  Prefer additive options with sane defaults over changing existing behavior.
