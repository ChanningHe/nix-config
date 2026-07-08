{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  makeWrapper,
  # runtime tools the scripts shell out to
  iproute2,
  kmod,
  ethtool,
  pciutils,
  util-linux,
  numactl,
  rdma-core,
  gawk,
  gnugrep,
  gnused,
  coreutils,
}:
let
  version = "24.10.1";
  pythonEnv = python3;
  # Everything the bash/python scripts call at runtime (ethtool, ip/tc/devlink,
  # lspci, modprobe, lscpu, awk, ...). `mst` (mstflint) is intentionally omitted;
  # the BlueField-specific tsbin scripts that need it won't fully work.
  runtimePath = lib.makeBinPath [
    iproute2
    kmod
    ethtool
    pciutils
    util-linux
    numactl
    rdma-core
    gawk
    gnugrep
    gnused
    coreutils
  ];
in
stdenv.mkDerivation {
  pname = "mlnx-tools";
  inherit version;

  src = fetchFromGitHub {
    owner = "Mellanox";
    repo = "mlnx-tools";
    rev = "v${version}";
    hash = "sha256-opz5uEDLR5qjTqf+ZrQdKOHnAPDaF8rDvzzzIA35sEk=";
  };

  nativeBuildInputs = [
    pythonEnv
    makeWrapper
  ];
  buildInputs = [ pythonEnv ];

  # The scripts use a few different python shebangs; normalise the ones
  # patchShebangs can't (bare `python` / `env python`) to python3.
  postPatch = ''
    for f in $(grep -rlE '^#! ?(/usr/bin/python|/usr/bin/env python)$' . || true); do
      substituteInPlace "$f" \
        --replace-quiet "/usr/bin/env python3" "${pythonEnv}/bin/python3" \
        --replace-quiet "/usr/bin/env python" "${pythonEnv}/bin/python3" \
        --replace-quiet "/usr/bin/python" "${pythonEnv}/bin/python3"
    done
  '';

  # Map the Makefile's FHS dirs into $out: all scripts -> $out/bin (so they land
  # on PATH; nix doesn't add sbin), python lib -> $out/share/mlnx-tools/python.
  installFlags = [
    "DESTDIR=${placeholder "out"}"
    "SBIN_DIR=/bin"
    "SBIN_TDIR=/bin"
    "BIN_DIR=/bin"
    "MAN8_DIR=/share/man/man8"
    "PYTHON_DIR=/share/mlnx-tools/python"
    "UDEV_DIR=/lib/udev"
    "SYSCONFDIR=/etc"
  ];

  postInstall = ''
    # The python tools find their library via a hardcoded /usr/share path
    # (guarded by os.path.exists). Point it at our actual lib dir.
    grep -rl '/usr/share/mlnx-tools/python' "$out" | while read -r f; do
      substituteInPlace "$f" \
        --replace '/usr/share/mlnx-tools/python' "$out/share/mlnx-tools/python"
    done

    patchShebangs "$out/bin"

    # Give every script the external tools it shells out to.
    for f in "$out"/bin/*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      wrapProgram "$f" --prefix PATH : "${runtimePath}"
    done
  '';

  meta = {
    homepage = "https://github.com/Mellanox/mlnx-tools";
    description = "Mellanox userland RDMA/InfiniBand tools (mlnx_qos, mlnx_tune, show_gids, set_irq_affinity, ...)";
    # Dual-licensed: "GPLv2 or BSD" per upstream.
    license = with lib.licenses; [
      gpl2Only
      bsd2
    ];
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
}
