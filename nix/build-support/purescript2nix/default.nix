{ purescript
, stdenv
, yaml2json
, jq
, fetchurl
, purescript-registry
, purescript-registry-index
, writeShellScriptBin
, nodejs
}:

let
  getRegistrySources =
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

      extra-packages = spagoYamlJSON.workspace.extra_packages or { };

      # Parse the package set from the registry at our requested version
      registryPackageSet = builtins.fromJSON (builtins.readFile "${purescript-registry}/package-sets/${registry-version}.json");

      readPackageByVersion = package: version:
        let
          meta = builtins.fromJSON (builtins.readFile "${purescript-registry}/metadata/${package}.json");
        in
        meta.published.${version} // {
          type = "registry";
          inherit version;
          location = meta.location;
        };
      readPackageInline = package: meta:
        let refLength = builtins.stringLength meta.ref;
        in
        {
          type = "inline";
          git = meta.git;
          ref = meta.ref;
          src =
            if refLength == 40
            then
            # Assume the "ref" is a commit hash if it's 40 characters long and use
            # it as a revision.
              builtins.fetchGit
                {
                  url = meta.git;
                  rev = meta.ref;
                  allRefs = true;
                }
            else
            # Use the ref as is and hope that the source is somewhat stable.
              builtins.fetchGit {
                url = meta.git;
                ref = meta.ref;
              };
        };


      readPackage = package: value:
        if builtins.typeOf value == "string"
        then readPackageByVersion package value
        else readPackageInline package value;

      # Fetch metadata about where to download each package in the package set as
      # well as the hash for the tarball to download.
      basePackages = builtins.mapAttrs readPackage registryPackageSet.packages;
      extraPackages = builtins.mapAttrs readPackage extra-packages;

      registryPackages = basePackages // extraPackages;

      # Lookup metadata in the registry-index by finding the line-separated JSON
      # manifest file in the repo matching the package and filtering out the object
      # matching the required version.
      lookupIndex = package: value:
        let
          version = value.version;
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
        value // {
          type = "registry";
          inherit version;
          pname = package;
          dependencies = builtins.attrNames meta.dependencies;
        };

      lookupSource = package: meta:
        let
          targetPursJSON = builtins.fromJSON (builtins.readFile "${meta.src}/purs.json");
          targetSpagoYAML = fromYAML (builtins.readFile "${meta.src}/spago.yaml");
          toList = x: if builtins.typeOf x == "list" then x else builtins.attrNames x;
          dependencies =
            if builtins.pathExists "${meta.src}/purs.json"
            then toList (targetPursJSON.dependencies or { })
            else toList (targetSpagoYAML.package.dependencies or [ ]);
        in
        meta // {
          type = "inline";
          pname = package;
          inherit dependencies;
        };

      lookupDeps = package: value:
        if value.type == "registry"
        then lookupIndex package value
        else lookupSource package value;

      # Fetch list of dependencies for each package in the package set.
      # This lookup is required to be done in the separate registry-index repo
      # because the package set metadata in the main repo doesn't contain
      # dependency information.
      registryDeps = builtins.mapAttrs lookupDeps registryPackages;

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

      # Get transitive closure of test dependencies
      testClosure = builtins.genericClosure {
        startSet = map closurePackage (spagoYamlJSON.package.test.dependencies ++ spagoYamlJSON.package.dependencies);
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
        then value.src
        else fetchPackageTarball value;

      # Packages are a flattened version of the closure.
      flatten = { key, package }: package // {
        url = "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz";
      };
      packages = map flatten closure;
      testPackages = map flatten testClosure;

      # Download the source code for each package in the closure.
      buildSources = map fetchPackage packages;
      testSources = map fetchPackage testPackages;
    in
    {
      inherit
        buildSources
        testSources
        spagoYamlJSON
        ;
    };

in
{
  build = args:
    let
      inherit (getRegistrySources args) buildSources spagoYamlJSON;

      # Generate the list of source globs as <package>/src/**/*.purs for each
      # downloaded package in the closure.
      registrySourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') buildSources;


      # Compile the main package by passing the source globs for each package in
      # the dependency closure as well as the sources in the main package.
      # TODO: pick purescript compiler based on package set compiler version (using easy-purescript-nix?)
      builtPureScriptCode = stdenv.mkDerivation {
        pname = spagoYamlJSON.package.name;
        version = spagoYamlJSON.package.version;
        src = args.src;

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
    builtPureScriptCode;
  test = args:
    let
      inherit (getRegistrySources args) testSources spagoYamlJSON;
      registrySourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') testSources;
      testMain = spagoYamlJSON.package.test.main or "Test.Main";
    in
    stdenv.mkDerivation {
      name = "test-${spagoYamlJSON.package.name}";
      src = args.src;
      buildInputs = [
        purescript
        nodejs
      ];
      buildPhase = ''
        purs compile ${toString registrySourceGlobs} "$src/test/**/*.purs"
      '';
      installPhase = ''
        node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from './output/${testMain}/index.js'; main();" 2>&1 > $out
      '';
    };

  develop = args:
    let
      inherit (getRegistrySources args) buildSources spagoYamlJSON;
      # Generate the list of source globs as <package>/src/**/*.purs for each
      # downloaded package in the closure.
      registrySourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') buildSources;
      purescript-compile = writeShellScriptBin "purescript-compile" ''
        set -x
        purs compile ${toString registrySourceGlobs} "$@"
      '';
    in
    stdenv.mkDerivation {
      name = "develop-${spagoYamlJSON.package.name}";
      buildInputs = [
        purescript
        purescript-compile
      ];
    };
}
