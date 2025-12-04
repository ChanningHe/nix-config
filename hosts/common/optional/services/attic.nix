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

  # Extract hostname from endpoint (e.g., "attic.hlpj.cc/homielab" -> "attic.hlpj.cc")
  endpointHost = lib.head (lib.splitString "/" endpoint);

  # Darwin users typically belong to group "staff" (gid 20)
  # NixOS users have a dedicated group matching their username
  userGroup = if isDarwin then "staff" else config.users.users.${config.hostSpec.username}.group;

  # netrc file path for Nix authentication
  netrcPath = "${config.hostSpec.home}/.config/attic/netrc";
in
{
  config = lib.mkIf (servername != "" && endpoint != "") (
    {
      environment.systemPackages = [
        pkgs.unstable.attic-client
      ];

      nix.settings = {
        # Prepend attic cache to the front (before office-cache and cache.nixos.org)
        substituters = lib.mkBefore [ "https://${endpoint}" ];
        trusted-public-keys = lib.mkBefore [
          "${endpointHost}:m9rTuwjBlORefVuHByPil1ymtrcqtJIQPh9AmXv93cU="
        ];
        # Point Nix to the netrc file for authentication
        netrc-file = netrcPath;
      };
    }
    // lib.optionalAttrs (!isDarwin) {
      # NixOS: Use sops templates and systemd tmpfiles

      # Generate attic CLI config (for manual attic commands)
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

      # Generate .netrc for Nix authentication
      sops.templates."attic-netrc" = lib.mkIf (config.sops.secrets ? "attic/token") {
        content = ''
          machine ${endpointHost}
          password ${config.sops.placeholder."attic/token"}
        '';
        owner = config.hostSpec.username;
        group = userGroup;
        mode = "0600"; # netrc requires 600 permissions
      };

      systemd.tmpfiles.rules = lib.mkIf (config.sops.secrets ? "attic/token") [
        "d ${config.hostSpec.home}/.config 0755 ${config.hostSpec.username} ${userGroup} -"
        "d ${config.hostSpec.home}/.config/attic 0755 ${config.hostSpec.username} ${userGroup} -"
        "L+ ${config.hostSpec.home}/.config/attic/config.toml - ${config.hostSpec.username} ${userGroup} - ${
          config.sops.templates."attic-config.toml".path
        }"
        # Link .netrc to home directory for Nix authentication
        "L+ ${netrcPath} - ${config.hostSpec.username} ${userGroup} - ${
          config.sops.templates."attic-netrc".path
        }"
      ];
    }
    // lib.optionalAttrs (isDarwin) {
      # Darwin: Manually generate config files from secret

      # FIXME: wait for sops-nix to be fixed on Darwin
      # system.activationScripts.postActivation.text = ''
      #   mkdir -p ${config.hostSpec.home}/.config/attic
      #   # 指向 sops 生成的路径
      #   ln -sf ${config.sops.templates."attic-config.toml".path} ${config.hostSpec.home}/.config/attic/config.toml
      # '';

      system.activationScripts.postActivation.text = ''
              TOKEN_PATH="/run/secrets/attic/token"
              CONFIG_DIR="${config.hostSpec.home}/.config/attic"
              CONFIG_FILE="$CONFIG_DIR/config.toml"
              NETRC_FILE="${netrcPath}"

              # Wait for sops secret to be available (simple check)
              if [ -f "$TOKEN_PATH" ]; then
                echo "Attic token found, generating config files..."
                mkdir -p "$CONFIG_DIR"

                # Read token content
                ATTIC_TOKEN=$(cat "$TOKEN_PATH")
                # Write attic CLI config file
                cat <<EOF > "$CONFIG_FILE"
        default-server = "${servername}"

        [servers.${servername}]
        endpoint = "https://${endpoint}"
        token = "$ATTIC_TOKEN"
        EOF

                # Write .netrc for Nix authentication
                cat <<EOF > "$NETRC_FILE"
        machine ${endpointHost}
        password $ATTIC_TOKEN
        EOF

                # Fix permissions
                chown -R ${config.hostSpec.username}:staff "$CONFIG_DIR"
                chmod 600 "$CONFIG_FILE"
                chown ${config.hostSpec.username}:staff "$NETRC_FILE"
                chmod 600 "$NETRC_FILE"
                echo "Attic config generated at $CONFIG_FILE"
                echo "Attic .netrc generated at $NETRC_FILE with 600 permissions"
              else
                echo "WARNING: Attic token NOT found at $TOKEN_PATH"
              fi
      '';
    }
  );
}
