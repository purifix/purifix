{ fetchurl, stdenv }:
{ packages, dependencies, storage-backend }:
let
  closurePackage = key: {
    key = key;
    package = packages.${key};
  };

  # Get transitive closure of dependencies starting with the dependencies of
  # our main package.
  closure = builtins.genericClosure {
    startSet = map closurePackage dependencies;
    operator = { key, package }: map closurePackage package.dependencies;
  };

  # This is not fetchTarball because the hashes in the registry refer to the
  # tarball itself not its extracted content.
  fetchPackageTarball = { pname, version, url, hash, ... }:
    stdenv.mkDerivation {
      inherit pname version;

      src = fetchurl {
        name = "${pname}-${version}.tar.gz";
        inherit url hash;
      };

      installPhase = ''
        cp -R . "$out"
      '';
    };

  fetchPackage = value:
    if value.type == "inline"
    then value
    else value // {
      src = fetchPackageTarball value;
    };

  # Packages are a flattened version of the closure.
  flatten = { key, package }: package // {
    url = storage-backend package;
  };
  package-closure = map fetchPackage (map flatten closure);

  # Download the source code for each package in the closure.
  sources = map (pkg: pkg.src) package-closure;
in
{
  packages = package-closure;
  inherit sources;
}
