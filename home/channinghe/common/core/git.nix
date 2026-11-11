# git is core no matter what but additional settings may could be added made in optional/foo   eg: development.nix
{
  ...
}:
{
  # Plain git here; optional/dev.nix switches to gitFull
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Channing He";
        email = "channinghey@gmail.com";
      };
      core.excludesFile = "~/.config/git/ignore";
      init.defaultBranch = "main";
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
      ".claude/"
      ".opencode/"
      ".DS_Store"
    ];
  };

}
