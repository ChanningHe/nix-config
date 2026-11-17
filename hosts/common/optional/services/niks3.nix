{
  config,
  lib,
  pkgs,
  inputs,
  isDarwin, # From specialArgs: avoids infinite recursion via config.hostSpec.isDarwin
  ...
}:
# niks3 binary cache client: substituter, gated reads, auto-upload of local builds.
# Mutually exclusive with attic.nix: both own nix.settings.netrc-file.
let
  hostName = config.hostSpec.hostName;
  # Per-host config takes precedence; fall back to global serviceInfo.niks3
  niks3Info =
    config.hostSpec.serviceInfo.${hostName}.niks3 or config.hostSpec.serviceInfo.niks3 or { };
  endpoint = niks3Info.endpoint or ""; # bare host, e.g. "niks3.example.com"
  publicKey = niks3Info.publicKey or ""; # "<key-name>:<base64>"
  serverUrl = "https://${endpoint}";

  system = pkgs.stdenv.hostPlatform.system;
  niks3Pkgs = inputs.niks3.packages.${system};

  userGroup = if isDarwin then "staff" else config.users.users.${config.hostSpec.username}.group;

  sopsFolder = config.hostSpec.sopsDir;
  hasSharedYaml = builtins.pathExists "${sopsFolder}/shared.yaml";
  tokenSecret = "niks3/token";

  autoUploadModule =
    if isDarwin then
      inputs.niks3.darwinModules.niks3-auto-upload
    else
      inputs.niks3.nixosModules.niks3-auto-upload;
in
{
  imports = [ autoUploadModule ];

  config = lib.mkIf (endpoint != "" && publicKey != "" && hasSharedYaml) {
    # Static API token: read (gated proxy) + write + admin.
    # User-owned for the CLI; root (nix-daemon, upload hook) reads it regardless.
    sops.secrets.${tokenSecret} = {
      sopsFile = "${sopsFolder}/shared.yaml";
      mode = "0400";
      owner = config.hostSpec.username;
      group = userGroup;
    };

    # Nix sends netrc credentials as HTTP Basic auth; niks3 takes the password as token
    sops.templates."niks3-netrc" = {
      content = ''
        machine ${endpoint}
        login nix
        password ${config.sops.placeholder.${tokenSecret}}
      '';
      mode = "0400";
    };

    nix.settings = {
      substituters = lib.mkBefore [ serverUrl ];
      trusted-public-keys = lib.mkBefore [ publicKey ];
      netrc-file = config.sops.templates."niks3-netrc".path;
    };

    # Push every locally built path via post-build-hook
    services.niks3-auto-upload = {
      enable = true;
      package = niks3Pkgs.niks3-hook;
      inherit serverUrl;
      authTokenFile = config.sops.secrets.${tokenSecret}.path;
    };

    # Manual `niks3 push` / `niks3 gc` with the same server and token
    environment.systemPackages = [ niks3Pkgs.niks3 ];
    environment.variables = {
      NIKS3_SERVER_URL = serverUrl;
      NIKS3_AUTH_TOKEN_FILE = config.sops.secrets.${tokenSecret}.path;
    };
  };
}
