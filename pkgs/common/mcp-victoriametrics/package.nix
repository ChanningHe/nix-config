{
  lib,
  unstable,
  fetchFromGitHub,
}:
let
  version = "1.20.2";
in
# go.mod requires Go 1.27.1; stable nixpkgs only ships 1.26.
unstable.buildGo127Module {
  pname = "mcp-victoriametrics";
  inherit version;

  src = fetchFromGitHub {
    owner = "VictoriaMetrics-Community";
    repo = "mcp-victoriametrics";
    rev = "v${version}";
    hash = "sha256-7kN7qwsvTL0scfBxMO/nrvikiysUxPY8nSFkhJsgGDM=";
  };

  # Upstream commits vendor/.
  vendorHash = null;

  subPackages = [ "cmd/mcp-victoriametrics" ];

  env.CGO_ENABLED = 0;

  # web/dist is not committed, so the optional web UI is empty; stdio MCP is unaffected.
  ldflags = [
    "-w"
    "-s"
    "-X main.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/VictoriaMetrics-Community/mcp-victoriametrics";
    license = lib.licenses.asl20;
    description = "MCP server for VictoriaMetrics";
    maintainers = [ ];
    mainProgram = "mcp-victoriametrics";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
