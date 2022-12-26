{ purescript
, stdenv
, yaml2json
, jq
, fetchurl
, purescript-registry
, purescript-registry-index
}:
{
  # Source of the input purescript package. Should be a path.
  #
  # Example: ./some/path/to/purescript-strings
  src
, spagoYaml ? "${src}/spago.yaml"
}:

let
  fromYAML = yaml:
    builtins.fromJSON (builtins.readFile (stdenv.mkDerivation {
      name = "fromYAML";
      phases = [ "buildPhase" ];
      buildPhase = "echo '${yaml}' | ${yaml2json}/bin/yaml2json > $out";
    }));

  spagoYamlJSON = fromYAML (builtins.readFile spagoYaml);

  registry-version = spagoYamlJSON.workspace.set.registry;

  registryPackageSet = builtins.fromJSON (builtins.readFile "${purescript-registry}/package-sets/${registry-version}.json");

  readPackageByVersion = package: version:
    let
      meta = builtins.fromJSON (builtins.readFile "${purescript-registry}/metadata/${package}.json");
    in
    meta.published.${version};

  # TODO: allow for fetching package from git specification
  basePackages = builtins.mapAttrs readPackageByVersion registryPackageSet.packages;

  # TODO: extend basePackages with extra_packages from the spago.yaml file
  registryPackages = basePackages;

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
  registryDeps = builtins.mapAttrs lookupIndex registryPackageSet.packages;

  closurePackage = key: {
    key = key;
    package = registryDeps.${key};
  };

  closure = builtins.genericClosure {
    startSet = map closurePackage spagoYamlJSON.package.dependencies;
    operator = { key, package }: map closurePackage package.dependencies;
  };

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

  packages = map
    ({ key, package }: package // {
      url = "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz";
    })
    closure;

  registrySources = map fetchPackage packages;
  registrySourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') registrySources;


  # TODO: pick purescript compiler based on package set compiler version
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
