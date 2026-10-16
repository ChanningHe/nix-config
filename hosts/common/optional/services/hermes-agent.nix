# Hermes Agent gateway (NousResearch) as a dedicated system service.
# https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup
#
# Config: /var/lib/hermes/.hermes/config.yaml
# Secrets: sops-nix secrets/<HostName>.yaml -> hermes/env
#
{
  config,
  inputs,
  pkgs,
  ...
}:
let
  sopsFile = "${builtins.toString inputs.nix-secrets}/secrets/${config.hostSpec.hostName}.yaml";
  envSecret = "hermes/env";
  # Fixed ids (repo convention uid == gid) for predictable file ownership.
  hermesId = 7000;
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    # Dashboard / API server stays off: hosts run without a firewall.
    backend.mode = "none";

    # Nix-declared keys win on every activation; all other keys in
    # config.yaml are preserved. Keep this list to security invariants only.
    settings.security = {
      redact_secrets = true;
      protected_instruction_files = true;
      approval.transport_fallback = "deny";
    };

    environmentFiles = [ config.sops.secrets.${envSecret}.path ];

    extraPackages = [
      config.nix.package
      pkgs.mcp-victoriametrics
    ];
  };

  # Upstream creates the user/group (createUser = true); only pin the ids.
  users.users.${config.services.hermes-agent.user}.uid = hermesId;
  users.groups.${config.services.hermes-agent.group}.gid = hermesId;

  # Root-only on disk; the activation script copies it into
  # $HERMES_HOME/.env (0640 hermes:hermes) after setupSecrets.
  sops.secrets.${envSecret} = {
    inherit sopsFile;
    owner = "root";
    mode = "0400";
    restartUnits = [ "hermes-agent.service" ];
  };

  # Relative limits so a runaway agent cannot starve the host.
  systemd.services.hermes-agent.serviceConfig = {
    MemoryMax = "50%";
    TasksMax = 1024;
    CPUWeight = 50;
    IOWeight = 50;
  };
}
