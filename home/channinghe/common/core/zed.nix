{ pkgs, ... }:
{
  home.file.".zed_server" = {
    source = "${pkgs.zed-editor.remote_server}/bin";
    # keeps the folder writable, but symlinks the binaries into it
    recursive = true;
  };
}
