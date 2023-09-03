{ fetchurl, stdenv, storage-backend }:
let
  # This is not fetchTarball because the hashes in the registry refer to the
  # tarball itself and not its extracted content.
  fetchPackageTarball = { pname, version, url, hash, ... }:
    stdenv.mkDerivation {
      inherit pname version;

      preferLocalBuild = true;
      allowSubstitutes = false;

      src = fetchurl {
        name = "${pname}-${version}.tar.gz";
        inherit url hash;
      };

      installPhase = ''
        cp -R . "$out"
      '';
    };

  fetchPackage = value: (
    if value.type == "inline"
    then value
    else value // {
      src = fetchPackageTarball (value // {
        url = storage-backend value;
      });
    }
  );
in
fetchPackage
