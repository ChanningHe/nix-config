# spawn — provision a NixOS host

`scripts/spawn.sh` (alias `just spawn`) provisions a NixOS host from nothing to
a fully deployed system. It is **state-driven**: instead of fixed phases and
flags like `--target-installer`, it probes the repo and the target, computes
what is still missing, shows a plan, and runs only those steps. This makes it
**idempotent** (re-running skips finished work) and **resumable** (pick up after
a failure by just running it again).

Most logic lives in Nix, not the script — see [Nix pieces](#nix-pieces).

## Steps

| Step | Does | Needs |
|------|------|-------|
| `scaffold` | Host config from the template: `hosts/nixos/<host>/default.nix`, `home/channinghe/<host>.nix`, a `network.nix` entry. Sets the disk `layout` and hostId, and `git add`s the new host. | — |
| `secrets` | Generate the SSH host key, write it to sops, copy the user password from `shared.yaml`, `just rekey`. | — |
| `disk` | SSH the target, pick the most stable disk alias (by-id > by-path > raw) and the primary NIC MAC, back-fill `default.nix` / `network.nix`. | `-d <ip>` |
| `install` | `nixos-anywhere`: disko + **nixos-facter** + install + reboot, using the **full** host config. Generates `facter.json`. | `-d <ip>`, secrets |

install uses the main flake (`.#<host>`), so the rebooted system is already
complete — there is no deploy step. To **update** an existing host later, use
`just deploy <host>` (see [below](#updating-an-existing-host)).

## State detection

The target is classified by SSH probe (`findmnt /`, `hostname`, `nixos-version`):

| State | Meaning | Effect |
|-------|---------|--------|
| `UNREACHABLE` | SSH down | disk/install error out |
| `NON_NIXOS` | generic Linux | install kexecs first |
| `INSTALLER` | root is tmpfs/overlay | install skips kexec |
| `INSTALLED_THIS` | installed, hostname matches | install is skipped |
| `INSTALLED_OTHER` | installed, different host | confirm before reinstalling |

This replaces the old `--target-installer` flag.

## Usage

```bash
just spawn Mola -d 10.40.20.101 --disk-layout ext4    # full run
just spawn Mola --only scaffold                        # just one step
just spawn Mola -d 10.40.20.101 --from install         # resume from install
```

Direct: `scripts/spawn.sh <host> [options]`.

### Options

```
-d, --destination <ip>     Target IP (needed for disk/install)
--port <port>              SSH port (default 22)
-u, --user <name>          Target user (default channinghe)

--disk-layout <ext4|btrfs|zfs|zfs-mirror>     (else prompted)
--ip4 --gateway4 --dns --host-id              scaffold values (else prompted)

--build-strategy <no-external|no-remote|on-target>   where/how install builds
                           (default no-external: build local via ssh builders)

--only <step>              run a single step
--from <step>              run from this step to the end
--skip <step>              skip a step (repeatable)

-y, --yes                  no confirmation
--dry-run                  detect + print the plan only
--debug                    set -x
```

## Interaction (plan / apply)

spawn detects state, prints a plan, and asks once before doing anything —
like `terraform plan`/`apply`:

```
════════ spawn: Mola ════════
  repo:    scaffold ✗   secrets ✗   disk-pinned ✗   facter ✗
  target:  10.40.20.101   state = INSTALLER   ...
Plan:
  [run]  scaffold — host config from template
  [run]  secrets — ssh host key -> sops
  [run]  disk — discover disk + NIC MAC, back-fill config
  [run]  install — nixos-anywhere ... (full config)  ⚠ WIPES DISK
Proceed with this plan? [y/N]
```

If [`gum`](https://github.com/charmbracelet/gum) is on `PATH`, prompts use it;
otherwise plain `read`. Run from inside `nix develop` (it needs sops, yq, jq,
ssh-to-age, etc.).

## Example: a fresh QEMU host (Mola)

1. Boot the target into a NixOS installer (any: the repo ISO, nixos-anywhere's,
   a kexec'd one). Note its IP.
2. Run the whole thing:
   ```bash
   just spawn Mola -d 10.40.20.101 --disk-layout ext4
   ```
   spawn scaffolds the config, writes secrets, discovers the disk (QEMU usually
   has no by-id → it picks by-path), then installs the full config with facter
   and reboots into the finished system.
3. `git add` the generated `hosts/nixos/Mola/` (incl. `facter.json`) and commit.

To re-run a single part: `just spawn Mola --only scaffold`, then inspect the
generated `hosts/nixos/Mola/default.nix`.

## Updating an existing host

deploy-rs nodes exist for every host (real IPs from nix-secrets), so spawn isn't
needed to *update* a host:

```bash
just deploy Toxotidae            # switch to the latest config, auto-rollback
```

Login is as the primary user (root SSH is disabled); deploy-rs sudo's to
activate, authenticating via the forwarded SSH agent (`pam_ssh_agent_auth`), so
the local agent must hold the user's key.

## Nix pieces

spawn is thin because the heavy lifting is declarative:

- **disk `layout`** → the host's `imports` calls
  [`lib.custom.bootDiskLayout`](../lib/boot-disk.nix) (e.g.
  `lib.custom.bootDiskLayout inputs { layout = "ext4"; disk = "/dev/..."; }`), which
  returns the matching disko layout **and** bootloader (plus the device) together
  — so a host can't be "installable but unbootable". It's a plain function (not a
  config-driven module) to keep the layout out of the module fixpoint (choosing
  `imports` from `config.*` would infinite-recurse). Existing hosts that don't
  call it are unaffected.
- **nixos-facter** replaces `hardware-configuration.nix`. The host imports
  `facter.json` (generated during install); the disk layout comes from disko, so
  there is no "hardware config scanned from the installer" hazard.
- **deploy-rs** ([`deploy.nix`](../deploy.nix)) powers `just deploy <host>` for
  updating existing hosts (not used by spawn itself). The CLI is pinned via
  `nix run .#deploy` to match the activation it builds.

## Caveats / things to validate

- **`facter.json` visibility**: it must be committed (or the tree dirty) for the
  flake build to see it. spawn `git add`s it after install.
- **agent-sudo**: every host must enable `security.pam.sshAgentAuth` (via
  `yubikey.nix`) and the local agent must hold the key, or deploy hangs on sudo.
- **x86_64-linux builds from a Mac** go through the configured remote builders.
- **magic-rollback** only catches connectivity loss at activation, not a config
  that fails to boot on the next reboot.

The legacy `scripts/provision-nixos.sh` (phase-based) is documented in
[add-new-host.md](add-new-host.md) and remains available.
