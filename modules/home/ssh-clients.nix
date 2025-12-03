# SSH Clients Configuration Module
# This module provides a way to selectively enable SSH client configurations
# from nix-secrets based on host-specific needs
#
# Host configs are written to ~/.ssh/config.d/hosts and included via
# the Include directive, avoiding conflicts with programs.ssh.matchBlocks
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

  # Format a single host block with proper indentation
  formatHostBlock =
    name: configStr:
    let
      # Trim and split into lines
      trimmed = lib.trim configStr;
      lines = lib.filter (l: l != "") (lib.splitString "\n" trimmed);
      # Indent each config line with 2 spaces (Host line itself is not indented)
      indentedLines = map (line: "  ${lib.trim line}") lines;
      configContent = lib.concatStringsSep "\n" indentedLines;
    in
    "Host ${name}\n${configContent}";

  # Generate complete SSH config file from enabled hosts
  generateSshConfig =
    enabledHosts:
    let
      # Filter only the enabled hosts
      enabledConfigs = lib.filterAttrs (name: _: builtins.elem name enabledHosts) sshClientsInfo;
      # Format each host block
      hostBlocks = lib.mapAttrsToList formatHostBlock enabledConfigs;
    in
    lib.concatStringsSep "\n\n" hostBlocks;
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
      # Write host configs to separate file that gets included by ssh.nix
      home.file.".ssh/config.d/hosts".text = generateSshConfig hostsToEnable;
    };
}
