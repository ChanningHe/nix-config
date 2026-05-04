# znapzend SSH plumbing module.
# Provides sops-managed identity key, system-wide ssh_config Host blocks (via
# programs.ssh.extraConfig), and pinned known_hosts so the root-run znapzend
# daemon can ssh to backup targets without prompting. The matching znapzend
# zetup destination must use `host = "<targets-key>"` so ssh resolves the alias.
{
  config,
  lib,
  ...
}:
let
  cfg = config.znapzendSsh;
in
{
  options.znapzendSsh = {
    enable = lib.mkEnableOption "znapzend SSH plumbing (sops key + programs.ssh.extraConfig Host blocks + known_hosts)";

    identity = {
      sopsKey = lib.mkOption {
        type = lib.types.str;
        default = "znapzend/ssh_private_key";
        description = "SOPS key path within sopsFile for the OpenSSH private key.";
      };
      sopsFile = lib.mkOption {
        type = lib.types.path;
        description = "SOPS-encrypted file containing the SSH private key.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/run/secrets/znapzend_ssh_key";
        description = "Decrypted key destination; referenced as IdentityFile.";
      };
    };

    targets = lib.mkOption {
      default = { };
      description = ''
        Per-destination SSH topology. Each attribute key is used verbatim as the
        ssh_config Host pattern; the matching znapzend zetup destination must set
        `host = "<key>"` (or supply the same string the ssh client will resolve).
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            hostName = lib.mkOption {
              type = lib.types.str;
              description = "Target IP or DNS name for the SSH HostName directive.";
            };
            user = lib.mkOption {
              type = lib.types.str;
              description = "Remote SSH user that owns the receive permissions.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 22;
            };
            hostPublicKey = lib.mkOption {
              type = lib.types.str;
              example = "ssh-ed25519 AAAAC3Nza... root@host";
              description = "Target's sshd host public key (from ssh-keyscan); pinned via programs.ssh.knownHosts.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${cfg.identity.sopsKey} = {
      sopsFile = cfg.identity.sopsFile;
      owner = "root";
      group = "root";
      mode = "0400";
      path = cfg.identity.path;
    };

    # Host blocks must land in /etc/ssh/ssh_config (NixOS does not Include
    # /etc/ssh/ssh_config.d/*). programs.ssh.extraConfig is placed at the top
    # of ssh_config, before `Host *`, so first-match-wins semantics apply.
    programs.ssh.extraConfig = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: t: ''
        Host ${name}
          HostName ${t.hostName}
          User ${t.user}
          Port ${toString t.port}
          IdentityFile ${cfg.identity.path}
          IdentitiesOnly yes
          StrictHostKeyChecking yes
          BatchMode yes
          ServerAliveInterval 30
          ServerAliveCountMax 3
      '') cfg.targets
    );

    programs.ssh.knownHosts = lib.mapAttrs (_name: t: {
      hostNames = lib.unique [
        _name
        t.hostName
      ];
      publicKey = t.hostPublicKey;
    }) cfg.targets;
  };
}
