# FIXME(starter): customize your bash preferences here
{
  programs.zsh = {
    enable = true;
    # enableCompletion = true;
    # autosuggestions.enable = true;
    # syntaxHighlighting.enable = true;
    shellAliases = {
      nxsw = "sudo nixos-rebuild switch";
      nx = "sudo nixos-rebuild";
    };

    initExtra = ''
      [[ ! $(command -v nix) && -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]] && source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
   '';
  };
# With Zplug:
  zplug = {
    enable = true;
    plugins = [
      {name = "zsh-users/zsh-autosuggestions";} # Simple plugin installation
      {
        name = "romkatv/powerlevel10k";
        tags = [ "as:theme" "depth:1" ];
      } # Installations with additional options. For the list of options, please refer to Zplug README.
    ];
  };

# With Oh-My-Zsh:
  oh-my-zsh = {
    enable = true;
    plugins = [
      "git"         # also requires `programs.git.enable = true;`
      #"thefuck"     # also requires `programs.thefuck.enable = true;` 
    ];
    theme = "robbyrussell";
  };

# With Antidote:
  antidote = {
    enable = true;
    plugins = [''
      zsh-users/zsh-autosuggestions
      ohmyzsh/ohmyzsh path:lib/git.zsh
    '']; # explanation of "path:..." and other options explained in Antidote README.
  };

  plugins = [
    {
      name = "zsh-autocomplete";
      src = pkgs.fetchFromGitHub {
        owner = "marlonrichert";
        repo = "zsh-autocomplete";
        rev = "23.07.13";
        sha256 = "sha256-/6V6IHwB5p0GT1u5SAiUa20LjFDSrMo731jFBq/bnpw=";
      };
    }
    {
      name = "powerlevel10k";
      src = pkgs.zsh-powerlevel10k;
      file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    }
    {
      name = "powerlevel10k-config";
      src = ./p10k-config;
      file = "p10k.zsh";
    }
    {
      name = "zsh-syntax-highlighting";
      src = pkgs.fetchFromGitHub {
        owner = "zsh-users";
        repo = "zsh-syntax-highlighting";
        rev = "0.8.0";
        sha256 = "sha256-iJdWopZwHpSyYl5/FQXEW7gl/SrKaYDEtTH9cGP7iPo=";
      };
    }
  ];
}
