{
  lib,
  ...
}:
{
  imports = lib.flatten [
    #
    # ========== Hardware ==========
    #
    #./hardware-configuration.nix
    #inputs.hardware.nixosModules.common-cpu-amd
    #inputs.hardware.nixosModules.common-cpu-intel
    #inputs.hardware.nixosModules.common-gpu-nvidia
    #inputs.hardware.nixosModules.common-gpu-intel
    #inputs.hardware.nixosModules.common-pc-ssd

    #
    # ========== Disk Layout ==========
    #
    #inputs.disko.nixosModules.disko

    #
    # ========== Misc Inputs ==========
    #

    (map lib.custom.relativeToRoot [
      #
      # ========== Required Configs ==========
      #
      "hosts/common/core"

      #
      # ========== Non-Primary Users to Create ==========
      #

      #
      # ========== Optional Configs ==========
      #
      "hosts/common/optional/services/attic.nix"
      "hosts/common/optional/darwin/darwin-smb.nix"
      "hosts/common/optional/darwin/dock-killer.nix"
      "hosts/common/optional/darwin/root-ssh-mapping.nix"
      #"hosts/common/optional/darwin/rosetta-builder.nix"
    ])
  ];

  #
  # ========== Host Specification ==========
  #

  hostSpec = {
    # !!![FIXME]!!!
    hostName = "ChanningdeMacBook-Pro";
    scaling = lib.mkForce "1";
    isDarwin = true;
    # loadUserAgeKey = true;
  };

  # Darwin uses integer stateVersion (1-6), not string like NixOS
  # See: https://daiderd.com/nix-darwin/manual/index.html#opt-system.stateVersion
  # 5 corresponds to nix-darwin 25.05
  system.stateVersion = 6;
}
