# SSH Clients Configuration Module
# This module provides a way to selectively enable SSH client configurations
# from nix-secrets based on host-specific needs
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.sshClients;

  # Read SSH clients info from nix-secrets
  sshClientsInfo = inputs.nix-secrets.sshClientsInfo or { };

  # Normalize SSH config string: trim and fix indentation
  normalizeConfig =
    config:
    let
      # Remove leading/trailing whitespace from the entire string
      trimmed = lib.trim config;
      # Split into lines
      lines = lib.splitString "\n" trimmed;
      # Remove leading whitespace from each line using replaceStrings
      trimLine =
        line:
        let
          # Remove all leading spaces
          stripped = builtins.match "[ \t]*(.*)" line;
        in
        if stripped != null then builtins.head stripped else line;
      # Remove leading whitespace from each line and re-indent with 2 spaces
      normalizedLines = map (line: "  ${trimLine line}") lines;
    in
    lib.concatStringsSep "\n" normalizedLines;

  # Filter and concatenate enabled SSH host configurations
  generateSshConfig =
    enabledHosts:
    let
      # Filter only the enabled hosts
      enabledConfigs = lib.filterAttrs (name: _: builtins.elem name enabledHosts) sshClientsInfo;
      # Convert to list of config strings with Host prefix and normalized indentation
      configList = lib.mapAttrsToList (
        name: config: "Host ${name}\n${normalizeConfig config}"
      ) enabledConfigs;
    in
    lib.concatStringsSep "\n\n" configList;
in
{
  options.sshClients = {
    enableAll = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable all SSH client configurations from nix-secrets.
        If true, all hosts in sshClientsInfo will be enabled.
        This option can be used together with enabledHosts.
      '';
    };

    enabledHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of SSH host names to enable from nix-secrets.
        Each host name should correspond to a key in sshClientsInfo.
      '';
      example = [
        "Host1"
        "Host2"
      ];
    };
  };

  config =
    let
      # Get all hosts if enableAll is true, otherwise use enabledHosts
      hostsToEnable = if cfg.enableAll then builtins.attrNames sshClientsInfo else cfg.enabledHosts;
    in
    lib.mkIf (hostsToEnable != [ ]) {
      programs.ssh.extraConfig = generateSshConfig hostsToEnable;
    };
}
