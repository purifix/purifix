{ fetchurl, lib, stdenv }:

# Download the source for a PureScript package defined in a PureScript package
# set.

{
  # PureScript package name. Should be a string.
  #
  # Example: "purescript-console"
  name
, # Hash for the package. Should be a string.
  #
  # Example: "sha256-gh81AQOF9o1zGyUNIF8Ticqaz8Nr+pz72DOUE2wadrA="
  hash
, # Repo for the package. Should be a string.
  #
  # Example: "https://github.com/purescript/purescript-console.git"
  repo
, # Version to download. Should be a string.
  #
  # Example: "v5.0.0"
  version
, ...
}:

let
  # Repo without the `.git` suffix.
  #
  # Example: "https://github.com/purescript/purescript-console"
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
