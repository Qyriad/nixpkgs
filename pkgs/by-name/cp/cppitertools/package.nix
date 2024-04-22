{
  lib,
  stdenv,
  cmake,
  boost,
  catch2,
  fetchFromGitHub,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "cppitertools";
  version = "2.1";

  src = fetchFromGitHub {
    owner = "ryanhaining";
    repo = "cppitertools";
    rev = "v${finalAttrs.version}";
    sha256 = "sha256-mii4xjxF1YC3H/TuO/o4cEz8bx2ko6U0eufqNVw5LNA=";
  };

  __structuredAttrs = true;
  strictDeps = true;

  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  nativeBuildInputs = [ cmake ];

  buildInputs = [ boost ];

  nativeCheckInputs = [ catch2 ];

  # Required on case-sensitive filesystems to not conflict with the Bazel BUILD
  # files that are also in that repo.
  cmakeBuildDir = "cmake-build";

  prePatch = lib.optionalString finalAttrs.doCheck ''
    # Required for tests.
    cp ${lib.getDev catch2}/include/catch2/catch.hpp test/
  '';

  checkPhase = ''
    runHook preCheck
    cmake -B build-test -S ../test
    cmake --build build-test -j$NIX_BUILD_CORES
    runHook postCheck
  '';

  meta = {
    homepage = "https://github.com/ryanhaining/cppitertools";
    description = "Implementation of Python itertools and builtin iteration functions for C++17";
    maintainers = with lib.maintainers; [ Qyriad ];
    license = with lib.licenses; bsd2;
  };
})
