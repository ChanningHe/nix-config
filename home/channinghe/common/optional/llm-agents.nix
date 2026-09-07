# LLM coding agents packaged by numtide/llm-agents.nix.
#
{ pkgs, inputs, ... }:
let
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  nix.settings = {
    extra-substituters = [ "https://cache.numtide.com?priority=100" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  home.packages = with agents; [
    claude-code
    codex
    pi
    #opencode

    # Claude Code ecosystem helpers
    # ccusage
    # ccstatusline
  ];
}
