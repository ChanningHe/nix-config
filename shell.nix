# Shell for bootstrapping flake-enabled nix and other tooling
{
  pkgs ?
    # If pkgs is not defined, instantiate nixpkgs from locked commit
    let
      lock = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked;
      nixpkgs = fetchTarball {
        url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
        sha256 = lock.narHash;
      };
    in
    import nixpkgs { overlays = [ ]; },
  checks,
  ...
}:
{
  default = pkgs.mkShell {
    NIX_CONFIG = "extra-experimental-features = nix-command flakes";
    BOOTSTRAP_USER = "channinghe";
    BOOTSTRAP_SSH_PORT = "22";
    BOOTSTRAP_SSH_KEY = "~/.ssh/id_yk288-main";

    nativeBuildInputs = builtins.attrValues {
      inherit (pkgs)
        # mkShell puts the minimal stdenv bash (no readline) on PATH, which
        # shadows the system bashInteractive and breaks flyline; re-shadow it
        bashInteractive
        nix
        home-manager
        nh
        git
        just
        sops
        jq # for JSON encoding multiline values in provision-nixos.sh
        yq-go # yq for yaml, used by helpers.sh (sops_update_age_key, creation rules)
        age # for bootstrap script
        ssh-to-age # for bootstrap script
        ;
    };

    # Thin pre-commit hook. Delegates the actual run to the `.#pre-commit`
    # devShell so shellcheck / nixfmt / deadnix / pre-commit-hooks are only
    # realized on the first `git commit` and cached in the store thereafter.
    shellHook = ''
      if [ -d .git ]; then
        cat > .git/hooks/pre-commit <<'HOOK'
      #!/bin/sh
      set -e
      cd "$(git rev-parse --show-toplevel)"
      exec nix --extra-experimental-features "nix-command flakes" \
        develop .#pre-commit --command \
        pre-commit run --hook-stage pre-commit --color always "$@"
      HOOK
        chmod +x .git/hooks/pre-commit
      fi
    '';
  };

  # Heavy pre-commit environment. Entered lazily by the thin git hook above,
  # or explicitly with `nix develop .#pre-commit` / `just check`.
  pre-commit = pkgs.mkShell {
    buildInputs = checks.pre-commit-check.enabledPackages ++ [ pkgs.pre-commit ];

    # Materialize the config JSON (same one git-hooks.nix would produce) and
    # register it as an indirect GC root so `nix-collect-garbage` keeps the
    # hook closure alive between runs.
    shellHook = ''
      nix-store --add-root .pre-commit-config.yaml --indirect --realise \
        ${checks.pre-commit-check.config.configFile} >/dev/null
    '';
  };
}
