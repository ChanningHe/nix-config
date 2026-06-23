{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "0.4.1";
in
buildGoModule {
  pname = "rdma_exporter";
  inherit version;

  src = fetchFromGitHub {
    owner = "yuuki";
    repo = "rdma_exporter";
    rev = "v${version}";
    hash = "sha256-Vvo/+XkQ5ehbpqdY+eH/VJk/SuoFbJtXr4dZsDKwBTY=";
  };

  vendorHash = "sha256-z/ncCtBROn3z2Q11hhzeZTpuDGSrpKs4095lNyLxT88=";

  ldflags = [
    "-w"
    "-s"
  ];

  meta = {
    homepage = "https://github.com/yuuki/rdma_exporter";
    description = "Prometheus exporter for RDMA (InfiniBand/RoCE) device metrics from sysfs";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "rdma_exporter";
    platforms = lib.platforms.linux;
  };
}
