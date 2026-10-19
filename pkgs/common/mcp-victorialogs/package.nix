{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "1.9.0";
in
buildGoModule {
  pname = "mcp-victorialogs";
  inherit version;

  src = fetchFromGitHub {
    owner = "VictoriaMetrics-Community";
    repo = "mcp-victorialogs";
    rev = "v${version}";
    hash = "sha256-esfd6Eg1j2BCgee1T5tiIdSPWVEBqhI4UGDKRFYyn3s=";
  };

  # Upstream commits vendor/.
  vendorHash = null;

  subPackages = [ "cmd/mcp-victorialogs" ];

  env.CGO_ENABLED = 0;

  # web/dist is not committed, so the optional web UI is empty; stdio MCP is unaffected.
  ldflags = [
    "-w"
    "-s"
    "-X main.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/VictoriaMetrics-Community/mcp-victorialogs";
    license = lib.licenses.asl20;
    description = "MCP server for VictoriaLogs";
    maintainers = [ ];
    mainProgram = "mcp-victorialogs";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
