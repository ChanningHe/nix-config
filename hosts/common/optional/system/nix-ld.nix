# Run dynamically linked binaries built for other distros
# (VS Code / Cursor remote server, prebuilt tools). Not needed for zed:
# its remote server comes from nixpkgs via home-manager.
{
  programs.nix-ld.enable = true;
}
