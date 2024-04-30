{
  lib,
  stdenv,
  fetchFromGitHub,
  bison,
  flex,
  readline,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "cdecl";
  version = "2.5";

  src = fetchFromGitHub {
    owner = "ridiculousfish";
    repo = "cdecl-blocks";
    # Latest commit as of 2024/04/30. Repo does not have any tags,
    # but the readme says version 2.5
    rev = "fe9747fb3280576415c9605c350a48091699fbfb";
    hash = "sha256-p6L/67/q/X7hOftVr9a5eQOn4UYe2ZqER7aZ6WoGFp8=";
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
    "CFLAGS=-DBSD -DUSE_READLINE -std=gnu89 -Wno-error=parentheses -Wno-error=incompatible-pointer-types -Wno-error-int-conversion"
    "LIBS=-lreadline"
  ];

  makeFlags = [
    "PREFIX=${placeholder "out"}"
    "BINDIR=${placeholder "out"}/bin"
    "MANDIR=${placeholder "out"}/man1"
    "CATDIR=${placeholder "out"}/cat1"
  ];

  preInstall = ''
    mkdir -p "$out/bin"
  '';

  meta = {
    description = "Translator English -- C/C++ declarations";
    license = lib.licenses.publicDomain;
    maintainers = with lib.maintainers; [ qyriad ];
    platforms = with lib.platforms; unix;
  };
})
