Notes
## NixOS

###
build nixos live installer image
```
nix build --impure .#nixosConfigurations.iso.config.system.build.isoImage
# or
# just iso
```

### Add New Hosts
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


## Darwin


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
