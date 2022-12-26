{ purescript
, stdenv
, yaml2json
, jq
, fetchurl
, purescript-registry
, purescript-registry-index
}:
{
  # Source of the input purescript package. Should be a path containing a
  # spago.yaml file.
  #
  # Example: ./some/path/to/purescript-strings
  src
, spagoYaml ? "${src}/spago.yaml"
}:

let
  # Parse text containing YAML content into a nix expression.
  fromYAML = yaml:
    builtins.fromJSON (builtins.readFile (stdenv.mkDerivation {
      name = "fromYAML";
      phases = [ "buildPhase" ];
      buildPhase = "echo '${yaml}' | ${yaml2json}/bin/yaml2json > $out";
    }));

  # Parse the spago.yaml package file into nix
  # TODO: Support the purs.json file instead/as well? It doesn't seem to
  # support extra_packages.
  spagoYamlJSON = fromYAML (builtins.readFile spagoYaml);

  # Package set version to use from the registry
  registry-version = spagoYamlJSON.workspace.set.registry;

  # Parse the package set from the registry at our requested version
  registryPackageSet = builtins.fromJSON (builtins.readFile "${purescript-registry}/package-sets/${registry-version}.json");

  readPackageByVersion = package: version:
    let
      meta = builtins.fromJSON (builtins.readFile "${purescript-registry}/metadata/${package}.json");
    in
    meta.published.${version};

  # Fetch metadata about where to download each package in the package set as
  # well as the hash for the tarball to download.
  # TODO: allow for fetching package from git specification
  basePackages = builtins.mapAttrs readPackageByVersion registryPackageSet.packages;

  # TODO: extend basePackages with extra_packages from the spago.yaml file
  registryPackages = basePackages;

  # Lookup metadata in the registry-index by finding the line-separated JSON
  # manifest file in the repo matching the package and filtering out the object
  # matching the required version.
  lookupIndex = package: version:
    let
      l = builtins.stringLength package;
      path =
        if l == 2 then "2/${package}"
        else if l == 3 then "3/${builtins.substring 0 1 package}/${package}"
        else "${builtins.substring 0 2 package}/${builtins.substring 2 2 package}/${package}";
      meta = builtins.fromJSON (builtins.readFile (stdenv.mkDerivation {
        name = "index-registry-meta-${package}";
        phases = [ "buildPhase" ];
        buildPhase = ''${jq}/bin/jq -s '.[] | select (.version == "${version}")' < "${purescript-registry-index}/${path}" > $out '';
      }));
    in
    registryPackages.${package} // {
      inherit version;
      pname = package;
      dependencies = builtins.attrNames meta.dependencies;
    };

  # Fetch list of dependencies for each package in the package set.
  # This lookup is required to be done in the separate registry-index repo
  # because the package set metadata in the main repo doesn't contain
  # dependency information.
  # TODO: Support getting the metadata directly from a git repo
  registryDeps = builtins.mapAttrs lookupIndex registryPackageSet.packages;

  closurePackage = key: {
    key = key;
    package = registryDeps.${key};
  };

  # Get transitive closure of dependencies starting with the dependencies of
  # our main package.
  closure = builtins.genericClosure {
    startSet = map closurePackage spagoYamlJSON.package.dependencies;
    operator = { key, package }: map closurePackage package.dependencies;
  };

  # This is not fetchTarball because the hashes in the registry refer to the
  # tarball itself not its extracted content.
  fetchPackage = { pname, version, url, hash, ... }:
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

  # Packages are a flattened version of the closure.
  packages = map
    ({ key, package }: package // {
      url = "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz";
    })
    closure;

  # Download the source code for each package in the closure.
  registrySources = map fetchPackage packages;

  # Generate the list of source globs as <package>/src/**/*.purs for each
  # downloaded package in the closure.
  registrySourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') registrySources;


  # Compile the main package by passing the source globs for each package in
  # the dependency closure as well as the sources in the main package.
  # TODO: pick purescript compiler based on package set compiler version (using easy-purescript-nix?)
  builtPureScriptCode = stdenv.mkDerivation {
    pname = spagoYamlJSON.package.name;
    version = spagoYamlJSON.package.version;
    inherit src;

    nativeBuildInputs = [
      purescript
    ];

    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      purs compile ${toString registrySourceGlobs} "$src/src/**/*.purs"
    '';
  };

in

builtPureScriptCode
