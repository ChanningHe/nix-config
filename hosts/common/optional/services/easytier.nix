{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  hostNetwork = config.hostSpec.networkInfo.hosts.${hostName} or { };
  hostEasytier = hostNetwork.easytier or { };

  # EasyTier instances
  easytierInstances = hostEasytier.instances or { };

  # LAN to EasyTier NAT config
  natEnabled = (hostEasytier.lan2etNat or { }).enable or false;
  tunInterface = (hostEasytier.lan2etNat or { }).tunInterface or "tun-et";

  # systemd units for the easytier instances, so NAT can order after them.
  instanceUnits = lib.mapAttrsToList (n: _: "easytier-${n}.service") easytierInstances;
in
{
  config = lib.mkIf (easytierInstances != { }) {
    services.easytier = {
      enable = true;
      package = pkgs.unstable.easytier;

      # All other configuration is in the user's TOML file at:
      # ${config.hostSpec.home}/.config/easytier/${instanceName}.toml
      instances = lib.mapAttrs (instanceName: instanceConfig: {
        enable = true;

        # Use config file from user's home directory
        # Default: $HOME/.config/easytier/${instanceName}.toml
        # User can override by setting configFile in network.nix easytier definition
        configFile =
          instanceConfig.configFile or "${config.hostSpec.home}/.config/easytier/${instanceName}.toml";
      }) easytierInstances;
    };

    systemd.tmpfiles.rules = lib.mapAttrsToList (
      instanceName: _:
      "d ${config.hostSpec.home}/.config/easytier 0755 ${config.hostSpec.username} ${
        config.users.users.${config.hostSpec.username}.group
      } -"
    ) easytierInstances;

    # Enable IP forwarding for EasyTier (use mkDefault to avoid conflicts)
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkDefault 1;
      "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
    };

    systemd.services = lib.mkMerge [
      # [WORKAROUND: systemd 258 + NFS activation freeze - line B]
      # Refs:
      #   https://discourse.nixos.org/t/failed-to-restart-sysinit-reactivation-target/58634/10
      #   https://github.com/NixOS/nixpkgs/issues/375376
      #
      # By default easytier unit uses stopIfChanged = true, which makes
      # activation do `systemctl stop` then `systemctl start`. During the gap
      # any NFS path routed over the tunnel hangs (held syscalls never return),
      # which can freeze sysinit-reactivation.target.
      #
      # Forcing single-step restart (like upstream tailscale does) keeps the
      # tunnel socket briefly alive across the transition. Combined with NFS
      # autofs in network-storage.nix, this closes the activation-time window.
      #
      # Safe for easytier: the binary is resilient to immediate re-exec and
      # restartTriggers upstream already pins restarts to config file changes.
      (lib.mapAttrs' (
        instanceName: _:
        lib.nameValuePair "easytier-${instanceName}" {
          stopIfChanged = false;
        }
      ) easytierInstances)

      # NAT rules for EasyTier tunnel
      (lib.mkIf natEnabled {
        easytier-nat = {
          description = "NAT rules for EasyTier";
          wantedBy = [ "multi-user.target" ];
          # network.target only means networking *started*, not that a default
          # route exists. Running this early, NETDEV resolves empty and the
          # FORWARD rule is added with a bogus interface, so NAT silently fails
          # until a manual restart. Wait for the network to be online (and the
          # tunnel instances to have started) so NETDEV is correct.
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ] ++ instanceUnits;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [
            pkgs.iproute2
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.iptables
          ];
          script = ''
            # Resolve the egress interface, waiting for the default route to
            # appear (grep -oP handles both "via GW dev X" and "dev X" forms,
            # unlike a fixed cut field).
            NETDEV=""
            for _ in $(seq 30); do
              NETDEV=$(ip -o route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' || true)
              [ -n "$NETDEV" ] && break
              sleep 1
            done
            if [ -z "$NETDEV" ]; then
              echo "easytier-nat: no default route; cannot set up NAT" >&2
              exit 1
            fi
            iptables -A FORWARD -i "$NETDEV" -o ${tunInterface} -j ACCEPT
            iptables -t nat -A POSTROUTING -o ${tunInterface} -j MASQUERADE
          '';
          preStop = ''
            NETDEV=$(ip -o route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' || true)
            iptables -D FORWARD -i "$NETDEV" -o ${tunInterface} -j ACCEPT 2>/dev/null || true
            iptables -t nat -D POSTROUTING -o ${tunInterface} -j MASQUERADE 2>/dev/null || true
          '';
        };
      })
    ];
  };
}
