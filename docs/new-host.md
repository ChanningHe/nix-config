# Add a New NixOS Host

`scripts/provision-nixos.sh` runs in four phases. The default `--phases 0,1,2,3`
runs them all; you can also run any subset.

| Phase | Does | Needs |
|-------|------|-------|
| 0 | Scaffold config: `hosts/nixos/<host>/default.nix`, `home/channinghe/<host>.nix`, `network.nix` entry (interactive network prompts) | — |
| 1 | Prepare secrets: generate SSH host key, update sops | — |
| 2 | Install: `nixos-anywhere` (disko → install → reboot) | `--disk`, `-d` |
| 3 | Deploy: regenerate `hardware-configuration.nix`, rsync config, `nixos-rebuild switch` | `-d` |

## Quick start

One command, all phases:

```bash
./scripts/provision-nixos.sh -n $newhost -d $newhostip \
  --disk-layout [ext4|btrfs|zfs|zfs-mirror] --disk /dev/sda [--disk2 /dev/disk/by-id/xxx]
```

## Step by step

```bash
# 0. Scaffold config (also: just new-host $newhost)
./scripts/provision-nixos.sh -n $newhost --phases 0

# --- edit hosts/nixos/$newhost/default.nix here (see "Before phase 2" below) ---

# 1. Secrets
./scripts/provision-nixos.sh -n $newhost --phases 1

# 2. Install to disk (kexec if not already in an installer; add --target-installer if it is)
./scripts/provision-nixos.sh -n $newhost -d $newhostip --phases 2 \
  --disk-layout [ext4|btrfs|zfs|zfs-mirror] --disk /dev/sda [--disk2 /dev/disk/by-id/xxx]

# 3. Deploy full config (run AFTER the host has rebooted into the installed system)
./scripts/provision-nixos.sh -n $newhost -d $newhostip --phases 3
```

## Before phase 2: pick a bootloader

The scaffold template ships **without** a bootloader, so add the module that
matches your disk layout to the host's `default.nix` imports — otherwise the
build fails with `boot.loader.grub.devices ... must be set`:

| Disk layout | Bootloader module |
|-------------|-------------------|
| ext4 / btrfs | `hosts/common/optional/system/systemd-boot.nix` |
| zfs | `hosts/common/optional/system/zfs-boot.nix` |
| zfs-mirror | `hosts/common/optional/system/zfs-mirror-boot.nix` |

## Gotchas

- **`hardware-configuration.nix` must come from the installed system.** Phase 3
  generates it via `nixos-generate-config` on the target, so it must run *after*
  phase 2 has installed NixOS and the machine rebooted into it. If phase 3 runs
  against a live installer, you get a bogus config (root on `tmpfs`, `/iso`,
  `squashfs`, no `/boot`) and the host won't boot. Never run phase 3 alone on an
  installer.

## Reinstall an existing host

Use `--migrate` to skip scaffold and restore the SSH key from sops instead of
generating a new one:

```bash
./scripts/provision-nixos.sh -n $host -d $hostip --migrate \
  --disk-layout zfs-mirror --disk /dev/disk/by-id/nvme-A --disk2 /dev/disk/by-id/nvme-B
```
