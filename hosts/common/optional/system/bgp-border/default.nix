# BGP border router role: networkd topology, nftables ruleset, forwarding
# switch and kernel hardening. Pair with services/bird.nix.
#
# Data: nix-secrets network.nix, networkInfo.hosts.<HostName>:
#   ip4 / gateway4 / ip6 / gateway6 / mac   edge NIC (underlay + management)
#   bgp.edge     { group; net6; }
#   bgp.transit  { group; mac; ip4; ip6; net6; router6; }   hands the prefixes to the home router
#   bgp.gre      { remote6; ip4; ip6; peer4; peer6; }       ip6gre tunnel to the upstream
#   bgp.dummy    { ip4; ip6; }                              stable identity (krt_prefsrc)
#   bgp.own      { v4; v6; }                                announced prefixes
#   bgp.mgmt4    [ cidr ]                                   allowed to SSH via the edge
#
# Invariant: forwarding is on only while nftables.service has a loaded ruleset.
# Physical NICs keep their kernel names; networkd puts them into an interface
# group by MAC and nftables matches the group.
#
# Manual rule change with auto-rollback (5 min):
#   sudo systemd-run --on-active=5min --unit=nft-rollback nft -f /etc/nftables-failsafe.conf
#   sudo nft -f /tmp/test.nft    # then ssh in again and check birdc
#   sudo systemctl stop nft-rollback.timer
# Persistent changes go through nftables.nft + deploy (reload is atomic).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  net = config.hostSpec.networkInfo.hosts.${config.hostSpec.hostName};
  inherit (net) bgp;
  forwarding =
    v: "${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=${v} net.ipv6.conf.all.forwarding=${v}";

  # Anything that would switch forwarding on outside nftables.service
  forwardSysctls = lib.filter (
    k: builtins.match "net\\.ipv[46]\\.(ip_forward|conf\\..*\\.forwarding)" k != null
  ) (lib.attrNames (lib.filterAttrs (_: v: v != null) config.boot.kernel.sysctl));
  forwardNetworkdKeys = [
    "IPForward"
    "IPv4Forwarding"
    "IPv6Forwarding"
    "IPMasquerade"
  ];
  networkdForwarding = lib.filter (cfg: lib.any (k: cfg ? ${k}) forwardNetworkdKeys) (
    [ config.systemd.network.config.networkConfig ]
    ++ lib.mapAttrsToList (_: n: n.networkConfig) config.systemd.network.networks
  );

  defines = ''
    define GRP_EDGE      = ${toString bgp.edge.group}
    define GRP_TRANSIT   = ${toString bgp.transit.group}
    define GRE_REMOTE_V6 = ${bgp.gre.remote6}
    define EDGE_V6       = ${bgp.edge.net6}
    define BGP_PEER_V4   = ${bgp.gre.peer4}
    define BGP_PEER_V6   = ${bgp.gre.peer6}
    define MGMT_V4       = { ${lib.concatStringsSep ", " bgp.mgmt4} }
    define OWN_V4        = ${bgp.own.v4}
    define OWN_V6        = ${bgp.own.v6}
    define TRANSIT_V6    = ${bgp.transit.net6}
    define ROUTER_V6     = ${bgp.transit.router6}
    define SSH_PORTS     = { ${lib.concatMapStringsSep ", " toString config.services.openssh.ports} }
  '';
in
{
  assertions = [
    {
      assertion = config.services.bird.enable;
      message = "bgp-border needs hosts/common/optional/services/bird.nix";
    }
    {
      assertion = !config.networking.firewall.enable;
      message = "bgp-border brings its own nftables ruleset; networking.firewall must stay off";
    }
    {
      # easytier.nix, wireguard.nix, ip-forward.nix and networking.nat all switch forwarding on
      assertion = forwardSysctls == [ ] && networkdForwarding == [ ];
      message = "bgp-border: forwarding is owned by nftables.service; drop what sets ${
        lib.concatStringsSep ", " (
          forwardSysctls ++ lib.optional (networkdForwarding != [ ]) "networkd forwarding"
        )
      }";
    }
  ];

  #
  # ========== Network ==========
  #
  systemd.network = {
    enable = true;

    # bird owns every route it installs; networkd must not flush them
    config.networkConfig = {
      ManageForeignRoutes = false;
      ManageForeignRoutingPolicyRules = false;
    };

    netdevs = {
      "30-dummy0".netdevConfig = {
        Name = "dummy0";
        Kind = "dummy";
      };

      # ip6gre costs 44 bytes, 1400 inner fits a 1500 path. EncapsulationLimit
      # off: the default adds an extension header firewalls like to drop.
      "30-gre1" = {
        netdevConfig = {
          Name = "gre1";
          Kind = "ip6gre";
          MTUBytes = "1400";
        };
        tunnelConfig = {
          Local = net.ip6;
          Remote = bgp.gre.remote6;
          TTL = 64;
          EncapsulationLimit = "none";
        };
      };
    };

    networks = {
      # Default route lives here; BGP routes are more specific. No IPv6 default
      # route: the /128 pins the tunnel peer to this leg (anti-recursion).
      "20-edge" = {
        matchConfig = {
          MACAddress = net.mac;
          Type = "ether";
        };
        linkConfig.Group = bgp.edge.group;
        networkConfig = {
          Address = [
            "${net.ip4}/24"
            "${net.ip6}/64"
          ];
          Gateway = net.gateway4;
          Tunnel = "gre1";
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "ipv6";
        };
        routes = [
          {
            Destination = "${bgp.gre.remote6}/128";
            Gateway = net.gateway6;
          }
        ];
      };

      # Numbered from the announced prefix so ICMP errors leave with a public
      # source. No gateway: bird installs the own-prefix routes.
      "20-transit" = {
        matchConfig = {
          MACAddress = bgp.transit.mac;
          Type = "ether";
        };
        linkConfig = {
          Group = bgp.transit.group;
          MTUBytes = "1400";
        };
        networkConfig = {
          Address = [
            bgp.transit.ip4
            bgp.transit.ip6
          ];
          DHCP = "no";
          IPv6AcceptRA = false;
        };
      };

      "30-gre1" = {
        matchConfig.Name = "gre1";
        networkConfig = {
          Address = [
            bgp.gre.ip4
            bgp.gre.ip6
          ];
          IPv6AcceptRA = false;
        };
      };

      # krt_prefsrc needs these before bird installs its first route
      "30-dummy0" = {
        matchConfig.Name = "dummy0";
        networkConfig.Address = [
          bgp.dummy.ip4
          bgp.dummy.ip6
        ];
      };
    };
  };

  #
  # ========== Firewall ==========
  #
  networking.firewall.enable = false;

  networking.nftables = {
    enable = true;
    ruleset = defines + builtins.readFile ./nftables.nft;
  };

  # ExecStartPost runs only after the ruleset loaded. On stop forwarding goes
  # off before the flush; ExecStopPost covers a failed start. Reload (deploy)
  # keeps forwarding on.
  systemd.services.nftables.serviceConfig = {
    ExecStartPost = [ (forwarding "1") ];
    ExecStop = lib.mkBefore [ (forwarding "0") ];
    ExecStopPost = [ (forwarding "0") ];
  };

  # The rollback target must parse: checked at build time like the main ruleset
  environment.etc."nftables-failsafe.conf".source = pkgs.writeTextFile {
    name = "nftables-failsafe.conf";
    text = defines + builtins.readFile ./nftables-failsafe.nft;
    # Same sandbox redirects as the main check (/etc/protocols for "gre")
    checkPhase = ''
      export NIX_REDIRECTS=${
        lib.escapeShellArg (
          lib.concatStringsSep ":" (
            lib.mapAttrsToList (n: v: "${n}=${v}") config.networking.nftables.checkRulesetRedirects
          )
        )
      }
      LD_PRELOAD="${pkgs.buildPackages.libredirect}/lib/libredirect.so ${pkgs.buildPackages.lklWithFirewall.lib}/lib/liblkl-hijack.so" \
        ${pkgs.buildPackages.nftables}/bin/nft --check --file $out
    '';
  };

  # Never announce from a box without its ruleset. After= only: Requires=
  # would flap BGP on every nftables restart.
  systemd.services.bird = {
    after = [ "nftables.service" ];
    # Stable path: a store path here would restart bird (flap BGP) on every nftables bump
    serviceConfig.ExecStartPre = "+/run/current-system/sw/bin/nft list chain inet filter forward";
  };

  #
  # ========== Kernel ==========
  #
  # Globs are expanded by systemd-sysctl and re-applied by udev to links
  # created later (gre1, dummy0).
  boot.kernel.sysctl = {
    # No two neighbours share a segment: never accept or send redirects
    "net.ipv4.conf.*.accept_redirects" = 0;
    "net.ipv6.conf.*.accept_redirects" = 0;
    "net.ipv4.conf.*.send_redirects" = 0;
    "net.ipv4.conf.*.accept_source_route" = 0;
    "net.ipv6.conf.*.accept_source_route" = 0;
    "net.ipv4.conf.*.log_martians" = 1;

    # Source validation is BCP38 in the forward chain; strict rp_filter would
    # drop sources missing from the BGP table, loose filters nothing.
    "net.ipv4.conf.*.rp_filter" = 0;

    # Answer ARP only for addresses on the receiving interface (not for
    # dummy0's address on the edge VLAN)
    "net.ipv4.conf.*.arp_ignore" = 1;
    "net.ipv4.conf.*.arp_announce" = 2;

    # BGP is TCP inside a 1400-byte tunnel: probe MSS after a PMTU black hole
    "net.ipv4.tcp_mtu_probing" = 1;

    "net.ipv6.conf.*.keep_addr_on_down" = 1;
  };
}
