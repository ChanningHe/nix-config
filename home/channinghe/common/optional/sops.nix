# home level sops. see hosts/common/optional/sops.nix for hosts level info and instructions
{
  inputs,
  config,
  ...
}:
let
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
  #secretsFilePath = "${sopsFolder}/secrets.yaml";
  secretsFilePath = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
  homeDirectory = config.home.homeDirectory;
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];
  sops = {
    # This is the location of the host specific age-key for the user "hiro" and will to have been extracted to this location via hosts/common/core/sops.nix on the host
    age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";

    defaultSopsFile = "${secretsFilePath}";
    validateSopsFiles = false;

    secrets = {
      "private_keys/channinghe" = {
        path = "${homeDirectory}/.ssh/id_ed25519-sk";
      };
    };
  };
}
