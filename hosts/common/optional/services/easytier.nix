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

    # NAT rules for EasyTier tunnel
    systemd.services.easytier-nat = lib.mkIf natEnabled {
      description = "NAT rules for EasyTier";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.iproute2
        pkgs.coreutils
        pkgs.iptables
      ];
      script = ''
        # Detect default route interface dynamically
        NETDEV=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
        iptables -A FORWARD -i "$NETDEV" -o ${tunInterface} -j ACCEPT
        iptables -t nat -A POSTROUTING -o ${tunInterface} -j MASQUERADE
      '';
      preStop = ''
        NETDEV=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
        iptables -D FORWARD -i "$NETDEV" -o ${tunInterface} -j ACCEPT 2>/dev/null || true
        iptables -t nat -D POSTROUTING -o ${tunInterface} -j MASQUERADE 2>/dev/null || true
      '';
    };
  };
}
