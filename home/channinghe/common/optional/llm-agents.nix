# LLM coding agents packaged by numtide/llm-agents.nix.
#
{ pkgs, inputs, ... }:
let
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
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
