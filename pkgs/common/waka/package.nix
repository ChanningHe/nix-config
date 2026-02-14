{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "0.1.1";
in
buildGoModule {
  pname = "waka";
  inherit version;

  src = fetchFromGitHub {
    owner = "kahnwong";
    repo = "waka";
    rev = "v${version}";
    hash = "sha256-iYUfUAA49k/44uXrV+PmzddOA+tQ+jRV/+R+6SEdEkU=";
  };

  vendorHash = "sha256-AOLYsDCz4ky9v5VdGoOPXiPx9WA5mDYr8DHKo5Www/c=";

  ldflags = [
    "-w"
    "-s"
    "-X github.com/kahnwong/waka/cmd.version=${version}"
  ];

  meta = {
    homepage = "https://github.com/kahnwong/waka";
    license = lib.licenses.mit;
    description = "CLI to get WakaTime stats";
    maintainers = [ ];
    mainProgram = "waka";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
