{
  lib,
  fetchFromGitHub,
  luaPackages,
  #buildLuarocksPackage,
  #argparse,
  #compat53,
  #hump,
  #lpeg,
  #luaOlder,
  #sirocco,
}:
let
  inherit (luaPackages) buildLuarocksPackage argparse compat53 lpeg hump luaOlder sirocco;
in
buildLuarocksPackage {
  pname = "croissant";
  version = "0.0.1-6";

  src = fetchFromGitHub {
    owner = "giann";
    repo = "croissant";
    rev = "65f2d3d61b9b13bdc380afc2eaf0c7c6ef461be7";
    hash = "sha256-6W4vdPN4pGB6czDth+z1lCMlgBB3O9YYa93qdRLjSHk=";
  };

  disabled = luaOlder "5.1";

  propagatedBuildInputs = [
    argparse
    compat53
    hump
    lpeg
    sirocco
  ];

  meta = {
    homepage = "https://github.com/giann/croissant";
    description = "A Lua REPL implemented in Lua";
    licenses = with lib.license; [ mit x11 ];
  };
}
