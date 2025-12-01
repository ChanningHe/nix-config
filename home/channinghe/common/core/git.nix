# git is core no matter what but additional settings may could be added made in optional/foo   eg: development.nix
{
  pkgs,
  ...
}:
{
  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    settings = {
      user = {
        name = "Channing He";
        email = "channinghey@gmail.com";
      };
    };
    ignores = [
      ".csvignore"
      # nix
      "*.drv"
      "result"
      # python
      "*.py?"
      "__pycache__/"
      ".venv/"
      # direnv
      ".direnv"
      ".cursor/"
    ];
  };

}
