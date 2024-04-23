{
  lib,
  stdenv,
  fetchurl,
  bison,
  flex,
  readline,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "cdecl";
  version = "2.5";

  src = fetchurl {
    url = "https://www.cdecl.org/files/cdecl-blocks-${finalAttrs.version}.tar.gz";
    sha256 = "1b7k0ra30hh8mg8fqv0f0yzkaac6lfg6n376drgbpxg4wwml1rly";
  };

  __structuredAttrs = true;
  stripDeps = true;

  patches = [ ./cdecl-2.5-lex.patch ];

  postPatch = ''
    substituteInPlace cdecl.c \
      --replace-fail "getline" "cdecl_getline"
  '';

  nativeBuildInputs = [ flex ];

  buildInputs = [
    bison
    readline
    ncurses
  ];

  buildFlags = [
    # Makefile hardcodes `gcc`.
    "CC=${lib.getExe stdenv.cc}"
    # "-DBSD" indicates compiling for a Unix system.
    "CFLAGS=-DBSD -DUSE_READLINE -std=gnu89 -Wno-parentheses -Wno-incompatible-function-pointer-types -Wno-int-conversion"
    "LIBS=-lreadline"
  ];

  makeFlags = [
    "PREFIX=${placeholder "out"}"
    "BINDIR=${placeholder "out"}/bin"
    "MANDIR=${placeholder "out"}/man1"
    "CATDIR=${placeholder "out"}/cat1"
  ];

  doCheck = true;

  checkTarget = "test";

  preInstall = ''
    mkdir -p "$out/bin"
  '';

  meta = {
    description = "Translator English -- C/C++ declarations";
    license = lib.licenses.publicDomain;
    maintainers = with lib.maintainers; [ qyriad ];
    platforms = lib.platforms.unix;
  };
})
