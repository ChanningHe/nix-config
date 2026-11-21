# shunt: local Claude Code router (subagents -> third-party provider).
# Config and keys are managed via `shunt provider/route/set-key`; run `shunt on` once.
{ inputs, ... }:
{
  imports = [ inputs.shunt.homeModules.default ];

  services.shunt.enable = true;
}
