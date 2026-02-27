Notes
## NixOS

###
build nixos live installer image
```
nix build --impure .#nixosConfigurations.iso.config.system.build.isoImage
# or
# just iso
```

# Add New Hosts

## Script

### NixOS
Add new host Config File
```
just new-host $newhostname
#   ./scripts/new-host.sh -n $newhostname
```

**One Line Command**

```
./scripts/provision-nixos.sh -n $newhostname --disk-layout [ext4/zfs/btrfs] --disk /dev/sda [--disk2 /dev/disk/by-id/xxx] -k [sshPrivateKey]
```

---

**Setup by Setup**

Create new host Sops-Secrets File && SHH-Host-Key && Netwrok config
```
./scripts/provision-nixos.sh --phases 0 -n $newhostname
```

Enter Kexec NixOS and rebuild to installer system.
```
./scripts/provision-nixos.sh --phases 1 -n $newhostname --disk-layout [ext4/zfs/btrfs] --disk /dev/sda [--disk2 /dev/disk/by-id/xxx] -k [sshPrivateKey]
```

Copy nix-config and rebuild to new host system.
```
./scripts/provision-nixos.sh --phases 2 -n $newhostname --disk-layout [ext4/zfs/btrfs] --disk /dev/sda [--disk2 /dev/disk/by-id/xxx] -k [sshPrivateKey]
```


## Manual

### NixOS
Activate the dev shell
```bash
nix develop --extra-experimental-features "nix-command flakes"
```

Switch to a specific host
```bash
nixos-rebuild switch --flake .#HostName
```

Create a hashed password
```bash
mkpasswd -s
```


### Darwin


Load the ssh-agent for nix-secrets
```bash
eval "$(ssh-agent -s)"
$(brew --prefix)/bin/ssh-add ~/.ssh/ssh-key
```

Download nix-darwin and rebuild the system
```bash
sudo nix run nix-darwin/nix-darwin-25.11#darwin-rebuild --extra-experimental-features "nix-command flakes" -- switch --flake .#$(scutil --get LocalHostName)
```

Rebuild the system with darwin-rebuild
```bash
sudo darwin-rebuild switch --flake .#$HOSTNAME
```
