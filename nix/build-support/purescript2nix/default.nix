{ callPackage, dhallDirectoryToNix, lib, purescript, stdenv, yaml2json, jq, fetchurl }:

# This is the main purescript2nix function.  See ../../overlay.nix for an
# example of how this can be used.

{
  # Package name.  Should be a string.
  #
  # Example: "purescript-strings"
  pname
, # Package version.  Should be a string.
  #
  # Example: "1.2.3"
  version ? ""
, format ? "spago"
, registry ? null
, registry-index ? null
, # Source of the input purescript package. Should be a path.
  #
  # Example: ./some/path/to/purescript-strings
  src
, spagoYaml ? "${src}/spago.yaml"
}:

let
  # This is the `spago.dhall` file translated to Nix.
  #
  # Example:
  #
  #   {
  #     name = "purescript-strings";
  #     dependencies = [ "console", "effect", "foldable-traversable", "prelude", "psci-support" ];
  #     packages = {
  #       abides = {
  #         dependencies = [ "enums", "foldable-traversable" ];
  #         hash = "sha256-nrZiUeIY7ciHtD4+4O5PB5GMJ+ZxAletbtOad/tXPWk=";
  #         repo = "https://github.com/athanclark/purescript-abides.git";
  #         version = "v0.0.1";
  #       };
  #       ...
  #     };
  #     sources = [ "src/**/*.purs", "test/**/*.purs" ];
  #   }
  spagoDhall = dhallDirectoryToNix { inherit src; file = "spago.dhall"; };

  # `spagoDhallDeps` is a list of all transitive dependencies of the package defined
  # in `spagoDhall`.
  #
  # In the above example, you can see that `console` is a direct dependency of
  # `purescript-strings`.  The first package in the following list is `console`.
  # This list of packages of course also contains all the transitive dependencies
  # of `console`:
  #
  # Example:
  #
  #   [
  #     {
  #       dependencies = [ "effect" "prelude" ];
  #       hash = "sha256-gh81AQOF9o1zGyUNIF8Ticqaz8Nr+pz72DOUE2wadrA=";
  #       name = "console";
  #       repo = "https://github.com/purescript/purescript-console.git";
  #       version = "v5.0.0";
  #     }
  #     ...
  #   ]
  #
  # The dependency graph is determined by figuring out the transitive
  # dependencies of `spagoDhall.dependencies` using the data in
  # `spagoDhall.packages`.
  spagoDhallDeps = import ./spagoDhallDependencyClosure.nix spagoDhall;

  fromYAML = yaml:
    builtins.fromJSON (builtins.readFile (stdenv.mkDerivation {
      name = "fromYAML";
      phases = [ "buildPhase" ];
      buildPhase = "echo '${yaml}' | ${yaml2json}/bin/yaml2json > $out";
    }));

  spagoYamlJSON = fromYAML (builtins.readFile spagoYaml);

  purescriptPackageToFOD = callPackage ./purescriptPackageToFOD.nix { };

  # List of derivations of the `spagoDhallDeps` source code.
  spagoDhallDepDrvs = map purescriptPackageToFOD spagoDhallDeps;

  # List of globs matching the source code for each of the transitive
  # dependencies from `spagoDhallDepDrvs`.
  #
  # Example:
  #   [
  #     "\"/nix/store/1sjyzw92sxil3yp5cndhaicl55m1djal-console-v5.0.0/src/**/*.purs\""
  #     "\"/nix/store/vhshp8vh061pfnkwwcvgx6zsrq8l0v3a-effect-v3.0.0/src/**/*.purs\""
  #     ...
  #   ]
  spagoSourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') spagoDhallDepDrvs;

  registry-version = spagoYamlJSON.workspace.set.registry;

  registryPackageSet = builtins.fromJSON (builtins.readFile "${registry}/package-sets/${registry-version}.json");

  registryPackages = builtins.mapAttrs
    (name: version:
      (builtins.fromJSON (builtins.readFile "${registry}/metadata/${name}.json")).published.${version}
    )
    registryPackageSet.packages;

  simplifyDependencies = attrs: builtins.attrNames attrs;

  lookupIndex = package: version:
    let
      l = builtins.stringLength package;
      path =
        if l == 2 then "2/${package}"
        else if l == 3 then "3/${builtins.substring 0 1 package}/${package}"
        else "${builtins.substring 0 2 package}/${builtins.substring 2 2 package}/${package}";
      meta = builtins.fromJSON (builtins.readFile (stdenv.mkDerivation {
        name = "index-registry-${package}";
        phases = [ "buildPhase" ];
        buildPhase = ''${jq}/bin/jq -s '.[] | select (.version == "${version}")' < "${registry-index}/${path}" > $out '';
      }));
    in
    registryPackages.${package} // {
      inherit version;
      pname = package;
      dependencies = simplifyDependencies meta.dependencies;
    };
  registryDeps = builtins.mapAttrs lookupIndex registryPackageSet.packages;

  closurePackage = key: {
    key = key;
    package = registryDeps.${key};
  };

  closure = builtins.genericClosure {
    startSet = map closurePackage spagoYamlJSON.package.dependencies;
    operator = { key, package }: builtins.trace package (map closurePackage package.dependencies);
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

  globsFor = {
    spago = spagoSourceGlobs;
    registry = builtins.trace (builtins.deepSeq packages packages) registrySourceGlobs;
  };


  sourceGlobs = globsFor.${format} or (builtins.throw "Unexpected format ${format}");

  builtPureScriptCode = stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [
      purescript
    ];

    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      purs compile ${toString sourceGlobs} "$src/src/**/*.purs"
    '';
  };

in

builtPureScriptCode
