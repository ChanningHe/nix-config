# Project-specific integration for Komodo Periphery
# This file handles:
# - Import of the pure NixOS module
# - sops-nix integration for secrets
# - hostSpec.serviceInfo configuration reading
# - Docker auto-enablement
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
  hostName = config.hostSpec.hostName;
  hostKomodo = config.hostSpec.serviceInfo.${hostName}.komodo or { };
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
  sopsFile = "${sopsFolder}/${hostName}.yaml";
  # hasSopsFile stays here: also used in the cfg.enable block below
  hasSopsFile = lib.pathExists sopsFile;
in
{
  imports = [
    (lib.custom.relativeToRoot "modules/hosts/nixos/komodo")
  ];

  config = lib.mkMerge [
    # Import settings from hostSpec.serviceInfo if komodo config exists
    (lib.mkIf (hostKomodo != { }) {
      services.komodo-periphery = {
        package = lib.mkDefault pkgs.unstable.komodo;
      }
      // (builtins.mapAttrs (_: lib.mkDefault) (builtins.removeAttrs hostKomodo [ "package" ]));
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
      users.users.${cfg.user} = lib.mkIf (cfg.user != "root" && cfg.user != "komodo-periphery") {
        extraGroups = [ "docker" ];
      };

      virtualisation.docker = {
        enable = lib.mkDefault true;
        autoPrune = {
          enable = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
        };
      };

      systemd.services.komodo-periphery = {
        after = lib.mkIf hasSopsFile [ "sops-nix.service" ];
        wants = lib.mkIf hasSopsFile [ "sops-nix.service" ];
        path = with pkgs; [
          git
          age
          sops
          docker
          bash
          openssh
        ];
      };
    })
  ];
}
