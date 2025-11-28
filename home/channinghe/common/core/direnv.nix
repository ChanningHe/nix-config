{
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true; # better than native direnv nix functionality - https://github.com/nix-community/nix-direnv

    # Performance optimization: reduce direnv log noise and improve caching
    config = {
      global = {
        # Suppress direnv log output for faster shell startup
        hide_env_diff = true;
        # Use extended cache for better performance
        strict_env = false;
      };
    };
  };
}
