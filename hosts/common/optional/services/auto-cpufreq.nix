{ ... }:
{
  services.auto-cpufreq.enable = true;

  # Optional tuning — see https://github.com/AdnanHodzic/auto-cpufreq
  # services.auto-cpufreq.settings = {
  #   battery = {
  #     governor = "powersave";
  #     turbo = "never";
  #   };
  #   charger = {
  #     governor = "performance";
  #     turbo = "auto";
  #   };
  # };
}
