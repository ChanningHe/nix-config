# Per-user ssh-agent on a fixed socket, run by launchd.
#
# - Fixed socket so nix-daemon (root) can reach it via IdentityAgent.
# - SSH_AUTH_SOCK / SSH_ASKPASS exported to shells and to GUI apps (launchctl setenv).
# - Keys are added on first use by the client's `AddKeysToAgent yes`.
# - Built-in askpass: touch prompts become notifications, other prompts are dialogs.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.sshAgent;

  askpass = pkgs.writeScript "ssh-askpass" ''
    #!/usr/bin/osascript
    on run argv
      set msg to item 1 of argv
      set promptKind to system attribute "SSH_ASKPASS_PROMPT"
      if promptKind is "none" then
        display notification msg with title "SSH"
        return
      end if
      activate
      if promptKind is "confirm" then
        display dialog msg buttons {"No", "Yes"} default button "Yes" cancel button "No"
        return
      end if
      if msg ends with ":" or msg ends with ": " then
        return text returned of (display dialog msg default answer "" with hidden answer)
      end if
      display dialog msg buttons {"No", "Yes"} default button "No" cancel button "No"
      return "yes"
    end run
  '';

  startAgent = pkgs.writeShellScript "ssh-agent-start" ''
    rm -f "${cfg.socket}"
    exec ${lib.getExe' pkgs.openssh "ssh-agent"} -D -a "${cfg.socket}"
  '';

  agentEnv = {
    SSH_AUTH_SOCK = cfg.socket;
    SSH_ASKPASS = "${askpass}";
    DISPLAY = ":0";
  };

  # launchd.user.envVariables only runs at switch time; this re-applies at every login.
  setGuiEnv = pkgs.writeShellScript "ssh-agent-setenv" (
    lib.concatStrings (
      lib.mapAttrsToList (k: v: "/bin/launchctl setenv ${k} ${lib.escapeShellArg v}\n") agentEnv
    )
  );
in
{
  options.sshAgent = {
    enable = lib.mkEnableOption "launchd-managed ssh-agent on a fixed socket";
    socket = lib.mkOption {
      type = lib.types.str;
      default = "/Users/${config.hostSpec.username}/.ssh/ssh-agent.sock";
      description = "Absolute path of the agent socket.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.user.agents.ssh-agent.serviceConfig = {
      ProgramArguments = [ "${startAgent}" ];
      EnvironmentVariables = agentEnv;
      RunAtLoad = true;
      KeepAlive = true;
    };

    launchd.user.agents.ssh-agent-env.serviceConfig = {
      ProgramArguments = [ "${setGuiEnv}" ];
      RunAtLoad = true;
    };

    environment.variables = agentEnv;
  };
}
