{ stdenv
, yaml2json
, jq
, fetchurl
, purescript-registry
, purescript-registry-index
, purescript2nix-compiler
, writeShellScriptBin
, nodejs
, lib
}:
{
  # Source of the input purescript package. Should be a path containing a
  # spago.yaml file.
  #
  # Example: ./some/path/to/purescript-strings
  src
, subdir ? ""
, spagoYaml ? "${src}/${subdir}/spago.yaml"
, backend ? null
, backendCommand ? lib.optionalString (backend != null) "${backend}/bin/${backend.pname}"
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

  package-set-config = spagoYaml.workspace.package_set or spagoYamlJSON.workspace.set;

  # Package set version to use from the registry
  registry-version = package-set-config.registry;

  extra-packages = spagoYamlJSON.workspace.extra_packages or { };

  # Parse the package set from the registry at our requested version
  package-set-file =
    if builtins.hasAttr "registry" package-set-config
    then "${purescript-registry}/package-sets/${registry-version}.json"
    else
      fetchurl {
        inherit (package-set-config) url hash;
      };
  registryPackageSet = builtins.fromJSON (builtins.readFile package-set-file);

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
    let
      refLength = builtins.stringLength meta.ref;
      packageConfig = {
        git =
          let repo =
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
          in
          {
            type = "inline";
            git = meta.git;
            ref = meta.ref;
            src =
              if builtins.hasAttr "subdir" meta
              then "${repo}/${meta.subdir}"
              else repo;
          } // lib.optionalAttrs (builtins.hasAttr "dependencies" meta) {
            inherit (meta) dependencies;
          };
        local =
          let
            absolute = builtins.substring 0 1 meta.path == "/";
            # Getting relative path is somewhat tricky because nix doesn't
            # support .. in what they call subpaths (the string appended to
            # the path).
            # We work around this limitation by using IFD and the `realpath` command.
            relative-path = builtins.readFile (stdenv.mkDerivation {
              name = "get-relative-path-${package}";
              phases = [ "installPhase" ];
              installPhase = ''
                realpath --relative-to="${src}" "${src}/${subdir}/${meta.path}" | tr -d '\n' > $out
              '';
            });
          in
          {
            type = "inline";
            src =
              if absolute then /. + meta.path
              else src + "/${relative-path}";
          } // lib.optionalAttrs (builtins.hasAttr "dependencies" meta) {
            inherit (meta) dependencies;
          };
      };
      package-type =
        if builtins.hasAttr "path" meta then "local"
        else if builtins.hasAttr "git" meta then "git"
        else builtins.throw "Cannot parse extra package ${package} with meta ${toString meta}";
    in
    packageConfig.${package-type};


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
    if builtins.hasAttr "dependencies" value
    then value # don't lookup dependencies if they are already declared
    else
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

  compiler-version = registryPackageSet.compiler;

  testSourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') testSources;
  buildSourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') buildSources;

  codegen = if backend == null then "js" else "corefn";
  package-src = src + "/${subdir}";

  testMain = spagoYamlJSON.package.test.main or "Test.Main";
  compiler = purescript2nix-compiler compiler-version;

  purescript-compile = writeShellScriptBin "purescript-compile" ''
    set -x
    purs compile --codegen ${codegen} ${toString buildSourceGlobs} "$@"
    ${backendCommand}
  '';

  # TODO: figure out how to run tests with other backends, js only for now
  test = stdenv.mkDerivation {
    name = "test-${spagoYamlJSON.package.name}";
    src = package-src;
    buildInputs = [
      compiler
      nodejs
    ];
    buildPhase = ''
      purs compile ${toString testSourceGlobs} "$src/test/**/*.purs"
    '';
    installPhase = ''
      node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from './output/${testMain}/index.js'; main();" | tee $out
    '';
  };

  develop = stdenv.mkDerivation {
    name = "develop-${spagoYamlJSON.package.name}";
    buildInputs = [
      compiler
      purescript-compile
    ];
  };

  build = stdenv.mkDerivation {
    pname = spagoYamlJSON.package.name;
    version = spagoYamlJSON.package.version;
    src = package-src;

    nativeBuildInputs = [
      compiler
    ];

    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      purs compile --codegen ${codegen} ${toString buildSourceGlobs} "$src/src/**/*.purs"
      ${backendCommand}
    '';
    passthru = {
      inherit test develop;
    };
  };
in
build
