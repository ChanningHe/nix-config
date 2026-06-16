# Reference (open-source / IBM) implementation of the Linear Tape File System.
# Provides `ltfs` (mount an LTO tape as a FUSE filesystem), `mkltfs` (format a
# tape) and `ltfsck` (check/repair). Distinct from nixpkgs' `hpe-ltfs`, which is
# HPE's prebuilt binary fork — this one is built from source for the `sg`
# (SCSI generic) backend, the path used by generic LTO drives on Linux.
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  fuse, # libfuse 2.x — configure wants `fuse >= 2.6.0` (fuse.pc), NOT fuse3
  icu, # genrb/pkgdata/icu-config at build time + libicu at link time
  libxml2, # LTFS index (XML) parser
  libuuid, # volume UUID generation (uuid.pc, from util-linux)
  net-snmp, # optional: SNMP traps for drive/medium errors
  snmpSupport ? false,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ltfs";
  version = "2.4.8.3-10521";

  src = fetchFromGitHub {
    owner = "LinearTapeFileSystem";
    repo = "ltfs";
    rev = "v${finalAttrs.version}";
    # uthash is a git submodule (src/libltfs/uthash_submodule); must be fetched.
    fetchSubmodules = true;
    hash = "sha256-O1BwzUsGtFPqpSZJqmYOVQAdYW7FBr2G61ZBimbrXMo=";
  };

  strictDeps = true;

  # nixpkgs' icu ships the `pkgdata` tool but NOT the `pkgdata.inc` options file
  # (nor the lib/icu/<ver> build tree), so `pkgdata -m static` — which LTFS uses
  # to compile each message catalog into a linkable object — dies with
  # U_FILE_ACCESS_ERROR. Reproduce pkgdata's own static pipeline by hand: pack
  # the resources into a common `.dat` (needs no pkgdata.inc), turn it into C
  # with genccode, then compile. The generated C includes <unicode/umachine.h>,
  # resolved via NIX_CFLAGS_COMPILE since icu is a buildInput, so a bare $CC works.
  postPatch = ''
    substituteInPlace messages/make_message_src.sh \
      --replace-fail \
        '-m static -q packagelist.txt >/dev/null' \
        '-m common -q packagelist.txt >/dev/null
    genccode -d . -n ''${BASENAME} -e ''${BASENAME} ''${BASENAME}.dat
    "''${CC:-cc}" -c ''${BASENAME}_dat.c -o ''${BASENAME}_dat.o'
  '';

  # autogen.sh is just aclocal/libtoolize/autoconf/autoheader/automake — i.e.
  # exactly what autoreconfHook runs, so we let the hook bootstrap instead.
  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    icu # genrb + pkgdata build the message resource bundles
  ];

  buildInputs = [
    fuse
    icu
    libxml2
    libuuid
  ]
  ++ lib.optionals snmpSupport [ net-snmp ];

  configureFlags = [
    (lib.enableFeature snmpSupport "snmp")
  ];

  enableParallelBuilding = true;

  meta = {
    homepage = "https://github.com/LinearTapeFileSystem/ltfs";
    description = "Open-source Linear Tape File System — mount LTO/IBM tape drives as a filesystem";
    longDescription = ''
      The Linear Tape File System (LTFS) presents an LTO or IBM tape, formatted
      with an LTFS index partition, as a mountable filesystem. This is the
      reference implementation maintained by IBM, built here with the generic
      `sg` SCSI backend for use with standard LTO drives on Linux.

      Key tools:
        - mkltfs  : format a tape with an LTFS volume
        - ltfs    : mount a tape via FUSE
        - ltfsck  : check and repair an LTFS volume
    '';
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    mainProgram = "ltfs";
    maintainers = [ ];
  };
})
