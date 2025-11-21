{
  config,
  lib,
  pkgs,
  isDarwin, # Use isDarwin from specialArgs to avoid infinite recursion
  ...
}:
let
  # Extract attic service info from hostSpec
  hostName = config.hostSpec.hostName;
  atticInfo = config.hostSpec.serviceInfo.${hostName}.attic or { };
  servername = atticInfo.servername or "";
  endpoint = atticInfo.endpoint or "";

  # Darwin users typically belong to group "staff" (gid 20)
  # NixOS users have a dedicated group matching their username
  userGroup = if isDarwin then "staff" else config.users.users.${config.hostSpec.username}.group;
in
{
  config = lib.mkIf (servername != "" && endpoint != "") (
    {
      environment.systemPackages = [
        pkgs.unstable.attic-client
      ];

      nix.settings = {
        substituters = [
          "https://${endpoint}"
          "https://cache.nixos.org/"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" # NixOS cache
          "${endpoint}:m9rTuwjBlORefVuHByPil1ymtrcqtJIQPh9AmXv93cU="
        ];
        trusted-users = [
          "root"
          "${config.hostSpec.username}"
        ];
      };
    }
    // lib.optionalAttrs (!isDarwin) {
      # NixOS: Use sops templates and systemd tmpfiles

      sops.templates."attic-config.toml" = lib.mkIf (config.sops.secrets ? "attic/token") {
        content = ''
          default-server = "${servername}"

          [servers.${servername}]
          endpoint = "https://${endpoint}"
          token = "${config.sops.placeholder."attic/token"}"
        '';
        owner = config.hostSpec.username;
        group = userGroup;
        mode = "0644";
      };

      systemd.tmpfiles.rules = lib.mkIf (config.sops.secrets ? "attic/token") [
        "d ${config.hostSpec.home}/.config 0755 ${config.hostSpec.username} ${userGroup} -"
        "d ${config.hostSpec.home}/.config/attic 0755 ${config.hostSpec.username} ${userGroup} -"
        "L+ ${config.hostSpec.home}/.config/attic/config.toml - ${config.hostSpec.username} ${userGroup} - ${
          config.sops.templates."attic-config.toml".path
        }"
      ];
    }
    // lib.optionalAttrs (isDarwin) {
      # Darwin: Manually generate config file from secret

      # FIXME: wait for sops-nix to be fixed on Darwin
      # system.activationScripts.postActivation.text = ''
      #   mkdir -p ${config.hostSpec.home}/.config/attic
      #   # 指向 sops 生成的路径
      #   ln -sf ${config.sops.templates."attic-config.toml".path} ${config.hostSpec.home}/.config/attic/config.toml
      # '';

      system.activationScripts.postActivation.text = ''
              echo "************** RUNNING ATTIC CONFIG SETUP **************"

              TOKEN_PATH="/run/secrets/attic/token"
              CONFIG_DIR="${config.hostSpec.home}/.config/attic"
              CONFIG_FILE="$CONFIG_DIR/config.toml"

              # Wait for sops secret to be available (simple check)
              if [ -f "$TOKEN_PATH" ]; then
                echo "Attic token found, generating config..."
                mkdir -p "$CONFIG_DIR"

                # Read token content
                ATTIC_TOKEN=$(cat "$TOKEN_PATH")

                # Write config file
                cat <<EOF > "$CONFIG_FILE"
        default-server = "${servername}"

        [servers.${servername}]
        endpoint = "https://${endpoint}"
        token = "$ATTIC_TOKEN"
        EOF

                # Fix permissions
                chown -R ${config.hostSpec.username}:staff "$CONFIG_DIR"
                chmod 600 "$CONFIG_FILE"
                echo "Attic config generated at $CONFIG_FILE"
              else
                echo "WARNING: Attic token NOT found at $TOKEN_PATH"
              fi
      '';
    }
  );
}
