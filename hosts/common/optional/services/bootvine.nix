# Boot/shutdown console animation showing the systemd job tree.
# https://codeberg.org/wvhulle/bootvine
{ inputs, ... }:
{
  imports = [ inputs.bootvine.nixosModules.default ];

  services.bootvine.enable = true;

  # Keep pre-bootvine kernel messages to errors
  boot.consoleLogLevel = 3;
}
