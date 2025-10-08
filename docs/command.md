Notes

Activate the dev shell
```
nix develop  --extra-experimental-features "nix-command flakes"
```

Switch to a specific host
```
nixos-rebuild switch --flake .#HostName
```

Create a hashed password
```
mkpasswd -s
```
