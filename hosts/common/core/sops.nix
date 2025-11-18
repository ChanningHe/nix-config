# FIXME(starter): The nix-config-starter repo assumes use of a `simple` nix-secrets scheme.
# The complex scheme will require modification to this file. Refer to the relevant files in
# EmergentMind's Nix-Config (the full version) to determine the required changes.

# hosts level sops. see home/[user]/common/optional/sops.nix for home/user level
{
  lib,
  inputs,
  config,
  ...
}:
let
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
  #sopsFolder = builtins.toString inputs.nix-secrets;
  #secretsFile = "${sopsFolder}/shared.yaml";
in
{
  #the import for inputs.sops-nix.nixosModules.sops is handled in hosts/common/core/default.nix so that it can be dynamically input according to the platform

  sops = {
    #defaultSopsFile = "${secretsFile}";
    # Only set default sops file if it exists, especially important for Darwin initial setup
    defaultSopsFile = if builtins.pathExists "${sopsFolder}/${config.hostSpec.hostName}.yaml"
      then "${sopsFolder}/${config.hostSpec.hostName}.yaml"
      else null;
    validateSopsFiles = false;
    age = {
      # automatically import host SSH keys as age keys
      # NOTE: Darwin and NixOS have different SSH key paths
      sshKeyPaths = if config.hostSpec.isDarwin then
        [
          # Darwin SSH keys are in a different location
          # and might not exist yet during initial setup
        ]
      else
        [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
    # secrets will be output to /run/secrets
    # e.g. /run/secrets/msmtp-password
    # secrets required for user creation are handled in respective ./users/<username>.nix files
    # because they will be output to /run/secrets-for-users and only when the user is assigned to a host.
  };

  # For home-manager a separate age key is used to decrypt secrets and must be placed onto the host. This is because
  # the user doesn't have read permission for the ssh service private key. However, we can bootstrap the age key from
  # the secrets decrypted by the host key, which allows home-manager secrets to work without manually copying over
  # the age key.
  sops.secrets = lib.mkMerge [
    (lib.mkIf config.hostSpec.loadUserAgeKey {
      # These age keys are are unique for the user on each host and are generated on their own (i.e. they are not derived
      # from an ssh key).

      "keys/age/${config.hostSpec.username}_${config.networking.hostName}" = {
        owner = config.users.users.${config.hostSpec.username}.name;
        # NOTE: group inheritance only works on NixOS
        # Darwin users don't have a 'group' attribute in the same way
      } // lib.optionalAttrs (config.users.users.${config.hostSpec.username} ? group) {
        inherit (config.users.users.${config.hostSpec.username}) group;
      } // {
        # We need to ensure the entire directory structure is that of the user...
        path = "${config.hostSpec.home}/.config/sops/age/keys.txt";
      };
    })
    # Password secrets are only for NixOS (Darwin handles authentication differently)
    (lib.mkIf (!config.hostSpec.isDarwin && builtins.pathExists "${sopsFolder}/${config.hostSpec.hostName}.yaml") {
      # extract password/username to /run/secrets-for-users/ so it can be used to create the user
      "passwords/${config.hostSpec.username}" = {
        #sopsFile = "${sopsFolder}/shared.yaml";
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        neededForUsers = true;
      };
    })
    # Shared secrets from shared.yaml (if it exists)
    # Skip on Darwin during initial setup when no age keys are configured
    (lib.mkIf (builtins.pathExists "${sopsFolder}/shared.yaml" && !config.hostSpec.isDarwin) {
      # Attic binary cache token
      "attic/token" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        mode = "0400";
        owner = config.hostSpec.username;
        group = config.hostSpec.username;
      };
    })
  ];
  # The containing folders are created as root and if this is the first ~/.config/ entry,
  # the ownership is busted and home-manager can't target because it can't write into .config...
  # In the future this may not be needed, depending on how https://github.com/Mic92/sops-nix/issues/381 is fixed
  # NOTE: This only works on NixOS where users have a 'group' attribute
  system.activationScripts.sopsSetAgeKeyOwnership = lib.mkIf (config.hostSpec.loadUserAgeKey && !config.hostSpec.isDarwin) (
    let
      ageFolder = "${config.hostSpec.home}/.config/sops/age";
      user = config.users.users.${config.hostSpec.username}.name;
      group = config.users.users.${config.hostSpec.username}.group;
    in
    ''
      mkdir -p ${ageFolder} || true
      chown -R ${user}:${group} ${config.hostSpec.home}/.config
    ''
  );
}
