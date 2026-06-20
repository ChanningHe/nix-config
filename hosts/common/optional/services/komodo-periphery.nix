# Project-specific integration for Komodo Periphery
# This file handles:
# - Import of the pure NixOS module
# - sops-nix integration for secrets
# - hostSpec.serviceInfo configuration reading
# - Container runtime wiring (docker, or rootless podman via cfg.dockerHost)
# - Any other nix-config specific logic
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.komodo-periphery;
  # On a podman host, komodo runs rootless as cfg.user (e.g. rl-man) and talks
  # to that user's socket; the path is derived from the user's static uid.
  usePodman = config.virtualisation.podman.enable;
  komodoUid = config.users.users.${cfg.user}.uid;
  komodoUidStr = if komodoUid == null then "INVALID" else toString komodoUid;
  hostName = config.hostSpec.hostName;
  hostKomodo = config.hostSpec.serviceInfo.${hostName}.komodo or { };
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
  sopsFile = "${sopsFolder}/${hostName}.yaml";
  # hasSopsFile stays here: also used in the cfg.enable block below
  hasSopsFile = lib.pathExists sopsFile;

  # Bridge serviceInfo.binaryPath (string) -> NixOS package derivation.
  # When binaryPath is set, create a thin wrapper that symlinks the external binary.
  komodoPackage =
    if hostKomodo ? binaryPath && hostKomodo.binaryPath != null then
      pkgs.runCommandLocal "komodo-periphery-custom" { } ''
        mkdir -p $out/bin
        ln -s ${lib.escapeShellArg hostKomodo.binaryPath} $out/bin/periphery
      ''
    else
      pkgs.unstable.komodo;
in
{
  imports = [
    (lib.custom.relativeToRoot "modules/hosts/nixos/komodo")
  ];

  config = lib.mkMerge [
    # Import settings from hostSpec.serviceInfo if komodo config exists
    (lib.mkIf (hostKomodo != { }) {
      services.komodo-periphery = {
        package = lib.mkDefault komodoPackage;
      }
      // (builtins.mapAttrs (_: lib.mkDefault) (
        builtins.removeAttrs hostKomodo [
          "package"
          "binaryPath"
        ]
      ));
    })

    # sops-nix integration (only if service is enabled and sops file exists)
    # sopsContent and hasXxx are inside this mkIf body so they are lazy:
    # builtins.readFile and string checks only run when actually needed.
    (lib.mkIf (cfg.enable && hasSopsFile) (
      let
        sopsContent = builtins.readFile sopsFile;
        # lib.hasInfix replaces builtins.match ".*x.*" — no regex compilation/backtracking
        hasKey = key: lib.all (part: lib.hasInfix "${part}:" sopsContent) (lib.splitString "/" key);

        hasPasskeys = hasKey "komodo/passkeys";
        hasPrivateKey = hasKey "komodo/private_key";
        hasCorePublicKeys = hasKey "komodo/core_public_keys";
        hasOnboardingKey = hasKey "komodo/onboarding_key";
        hasSopsAgeKey = hasKey "komodo/sops_age_key";
        hasSslKey = hasKey "komodo/ssl_key";
        hasSslCert = hasKey "komodo/ssl_cert";

        # Common secret attrs; avoids repeating owner/group/mode 7 times
        mkSecret =
          extra:
          {
            inherit sopsFile;
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          }
          // extra;
      in
      {
        # builtins.listToAttrs builds the attrset in one pass instead of 7x // copies
        sops.secrets = builtins.listToAttrs (
          lib.optionals (cfg.inbound.ssl.enable && hasSslKey) [
            {
              name = "komodo/ssl_key";
              value = mkSecret { path = "${cfg.rootDirectory}/ssl/key.pem"; };
            }
          ]
          ++ lib.optionals (cfg.inbound.ssl.enable && hasSslCert) [
            {
              name = "komodo/ssl_cert";
              value = mkSecret { path = "${cfg.rootDirectory}/ssl/cert.pem"; };
            }
          ]
          ++ lib.optionals hasPasskeys [
            {
              name = "komodo/passkeys";
              value = mkSecret { };
            }
          ]
          ++ lib.optionals hasPrivateKey [
            {
              name = "komodo/private_key";
              value = mkSecret { };
            }
          ]
          ++ lib.optionals hasCorePublicKeys [
            {
              name = "komodo/core_public_keys";
              value = mkSecret { };
            }
          ]
          ++ lib.optionals hasOnboardingKey [
            {
              name = "komodo/onboarding_key";
              value = mkSecret { };
            }
          ]
          ++ lib.optionals hasSopsAgeKey [
            {
              name = "komodo/sops_age_key";
              value = mkSecret { };
            }
          ]
        );

        services.komodo-periphery = lib.mkMerge [
          (lib.mkIf (cfg.inbound.ssl.enable && hasSslKey && hasSslCert) {
            inbound.ssl = {
              keyFile = lib.mkForce config.sops.secrets."komodo/ssl_key".path;
              certFile = lib.mkForce config.sops.secrets."komodo/ssl_cert".path;
            };
          })
          (lib.mkIf hasPasskeys {
            passkeyFiles = config.sops.secrets."komodo/passkeys".path;
          })
          (lib.mkIf hasPrivateKey {
            auth.privateKey = "file:${config.sops.secrets."komodo/private_key".path}";
          })
          (lib.mkIf hasCorePublicKeys {
            auth.corePublicKeys = [ "file:${config.sops.secrets."komodo/core_public_keys".path}" ];
          })
          (lib.mkIf hasOnboardingKey {
            outbound.onboardingKeyFile = config.sops.secrets."komodo/onboarding_key".path;
          })
          (lib.mkIf hasSopsAgeKey {
            environment = lib.mkDefault {
              SOPS_AGE_KEY_FILE = config.sops.secrets."komodo/sops_age_key".path;
            };
          })
        ];
      }
    ))

    (lib.mkIf cfg.enable {
      # On podman, komodo must run as the rootless user that owns the socket.
      assertions = lib.optional usePodman {
        assertion = komodoUid != null;
        message = "komodo-periphery on podman must run as a normal user with a static uid (set services.komodo-periphery.user to e.g. rl-man); user '${cfg.user}' has none.";
      };

      # Setting dockerHost flips the base module out of docker mode (drops the
      # docker daemon/group/service deps) and injects DOCKER_HOST. komodo owns
      # the socket as cfg.user, so no extra group is needed.
      services.komodo-periphery.dockerHost = lib.mkIf usePodman "unix:///run/user/${komodoUidStr}/podman/podman.sock";

      # Only the docker daemon needs a group membership; podman is socket-owned.
      users.users.${cfg.user} =
        lib.mkIf (!usePodman && cfg.user != "root" && cfg.user != "komodo-periphery")
          {
            extraGroups = [ "docker" ];
          };

      # Only manage the docker daemon when this host is not on podman.
      virtualisation.docker = lib.mkIf (!usePodman) {
        enable = lib.mkDefault true;
        autoPrune = {
          enable = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
        };
      };

      systemd.services.komodo-periphery = {
        # Do NOT order against user@<uid>.service: a system unit referencing a
        # user-manager template instance trips a switch-to-configuration
        # infinite loop. komodo retries (Restart=on-failure) until the socket is up.
        after = lib.optional hasSopsFile "sops-nix.service";
        wants = lib.optional hasSopsFile "sops-nix.service";

        # Rootless as rl-man needs its real home (podman storage, terminal
        # shells) and /run/user/<uid> (the socket); ProtectHome=true hides both.
        serviceConfig.ProtectHome = lib.mkIf usePodman (lib.mkForce false);

        # periphery spawns child processes (openssl for SSL cert gen, git, the
        # container CLI, etc.) via $PATH — NOT ExecSearchPath, which only resolves
        # the ExecStart= command name.
        path =
          (with pkgs; [
            git
            age
            sops
            openssh
            openssl
            docker-compose
          ])
          #++ lib.optional (!usePodman) pkgs.docker
          ++ [
            "/run/wrappers"
            "/run/current-system/sw"
          ];
      };
    })
  ];
}
