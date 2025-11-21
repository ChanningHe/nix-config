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


## Darwin

Install the darwin-rebuild command && rebuild the system
```
sudo nix run nix-darwin/nix-darwin-25.05#darwin-rebuild --extra-experimental-features "nix-command flakes" -- switch --flake .#$(scutil --get LocalHostName)
```

```
sudo darwin-rebuild switch --flake .#$HOSTNAME
```
