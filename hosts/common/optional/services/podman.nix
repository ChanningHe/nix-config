{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  podmanConfig = config.hostSpec.serviceInfo.${hostname}.podman or { };

  # Defaults to "rl-man"; override per-host via serviceInfo.<host>.podman.runner.
  runner = podmanConfig.runner or "rl-man";
  runnerUid = config.users.users.${runner}.uid;
in
{
  # Let non-root containers bind privileged ports (>=80). Tradeoff: any
  # unprivileged process can now bind 80-1023, not just podman.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = lib.mkDefault 80;

  virtualisation.podman = {
    enable = lib.mkDefault true;

    # `docker` command alias.
    dockerCompat = lib.mkDefault true;

    # Inter-container name resolution on the default network (netavark).
    defaultNetwork.settings.dns_enabled = lib.mkDefault (podmanConfig.dnsEnabled or true);

    autoPrune = {
      enable = lib.mkDefault true;
      dates = lib.mkDefault "weekly";
    };
  };

  # podman host: no rootful docker daemon competing for the socket.
  virtualisation.docker.enable = lib.mkForce false;

  # `podman compose` needs an external provider. Replaces the old docker-compose.
  environment.systemPackages = [ pkgs.podman-compose ];

  # Keep the runner's user manager alive at boot so its rootless podman socket
  # and containers come up without an interactive login.
  users.users.${runner}.linger = true;

  # Start the runner's --restart=always containers on boot, stop them on
  # shutdown. System service running *as* the rootless user, so XDG_RUNTIME_DIR
  # is set explicitly. Must NOT order against user@${uid}.service: a system unit
  # referencing a user-manager template instance sends the rust
  # switch-to-configuration into an infinite loop. logind creates
  # /run/user/${uid} early for lingering users; we just wait for the socket.
  systemd.services."podman-autostart-${runner}" = {
    description = "Start ${runner}'s rootless containers with restart policy";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    # Rootless podman needs the *setuid* newuidmap/newgidmap (in /run/wrappers/bin)
    # to set up the user namespace. systemd.services.path appends "/bin", so pass
    # "/run/wrappers" (not config.security.wrapperDir, which would yield
    # /run/wrappers/bin/bin); it must come first so the setuid copies beat the
    # plain ones in the system profile.
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = runner;
      Environment = "XDG_RUNTIME_DIR=/run/user/${toString runnerUid}";
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 30); do [ -S \"$XDG_RUNTIME_DIR/podman/podman.sock\" ] && break; sleep 1; done; exit 0'";
      ExecStart = "${lib.getExe pkgs.podman} start --all --filter restart-policy=always";
      ExecStop = "${lib.getExe pkgs.podman} stop --all";
    };
  };

  # The per-user podman API service (drives container creation for komodo) also
  # needs the setuid newuidmap on PATH (see the autostart service above).
  systemd.user.services.podman.path = [
    "/run/wrappers"
    "/run/current-system/sw"
  ];
}
