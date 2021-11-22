{ fetchurl, lib, stdenv }:

{ name, hash, repo, version, ... }:

let
  repoWithoutDotGit = lib.removeSuffix ".git" repo;

in
stdenv.mkDerivation {
  pname = name;
  inherit version;

  src = fetchurl {
    name = "${name}-${version}.tar.gz";
    url = "${repoWithoutDotGit}/archive/${version}.tar.gz";
    inherit hash;
  };

  installPhase = ''
    cp -R . "$out"
  '';
}
