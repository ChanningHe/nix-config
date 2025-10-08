# FIXME(starter): customize your bash preferences here
{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = {
      nxsw = "sudo nixos-rebuild switch";
      nx = "sudo nixos-rebuild";
    };

    initExtra = ''
   '';
  };
  # shell tools
  programs.starship = {
    enable = true;
    #presets = ["no-runtime-versions"];
    # 自定义配置
    settings = {
      add_newline = false;
      aws.disabled = true;
      gcloud.disabled = true;
      #保留路径截断5
      directory.truncation_length = 5;
      line_break.disabled = true;
    };
  };
}
