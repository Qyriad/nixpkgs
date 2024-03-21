{ lib
, buildNpmPackage
, fetchFromGitHub
, writeText
, jq
, python3
, pkg-config
, pixman
, cairo
, pango
, stdenvNoCC
, nodejs
, darwin
, conf ? { }
}:

let
  configOverrides = writeText "cinny-config-overrides.json" (builtins.toJSON conf);
  inherit (nodejs.pkgs) node-gyp;
in
buildNpmPackage rec {
  pname = "cinny";
  version = "3.1.0";

  outputs = [ "out" "dev" ];

  src = fetchFromGitHub {
    owner = "cinnyapp";
    repo = "cinny";
    rev = "v${version}";
    hash = "sha256-GcygxK9NcGlv4rwxQCJqi0BhNlOTFxjGB8mbfTaBMOk=";
  };

  patches = [
    ./vite-svg-no-sourcemap.patch
  ];

  npmDepsHash = "sha256-4R+To2LhcnEM9x1noo6MhCckyBKgPWiAi7zgDqAmaN0=";

  dontNpmPrune = true;

  nativeBuildInputs = [
    jq
    python3
    pkg-config
    nodejs
    node-gyp
  ];

  buildInputs = [
    pixman
    cairo
    pango
  ] ++ lib.optionals stdenvNoCC.isDarwin [
    darwin.apple_sdk.frameworks.CoreText
  ];

  npmRebuildFlags = [
    "--ignore-scripts"
  ];

  postInstall = ''
    # npmInstallHook automatically places things in $out, which is where we ant
    # Vite's artifacts to go.
    # Conversely, we want npm's artifacts to go in #dev, so:
    mv -v "$out" "$dev"
    cp -r ./dist "$out"
    # Using the npm artifacts is also always going to require the web artifacts too,
    # so let's symlink the web artifacts under $dev.
    ln -sv "$out" "$dev/lib/node_modules/cinny/dist"
  '';

  meta = with lib; {
    description = "Yet another Matrix client for the web";
    homepage = "https://cinny.in/";
    maintainers = with maintainers; [ abbe ashkitten qyriad ];
    license = licenses.agpl3Only;
    platforms = platforms.all;
  };
}
