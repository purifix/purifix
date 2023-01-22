{ stdenv
, callPackage
, purescript2nix-compiler
, writeShellScriptBin
, nodejs
, lib
, fromYAML
, purescript-registry
, purescript-registry-index
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
, storage-backend ? package: "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz"
}:

let

  # Parse the spago.yaml package file into nix
  # TODO: Support the purs.json file instead/as well? It doesn't seem to
  # support extra_packages.
  spagoYamlJSON = fromYAML (builtins.readFile spagoYaml);

  package-set-config = spagoYaml.workspace.package_set or spagoYamlJSON.workspace.set;
  extra-packages = spagoYamlJSON.workspace.extra_packages or { };

  inherit (callPackage ./get-package-set.nix
    { inherit fromYAML purescript-registry purescript-registry-index; }
    { inherit package-set-config extra-packages src subdir; }) packages package-set;

  fetch-sources = callPackage ./fetch-sources.nix { };

  # Download the source code for each package in the transitive closure
  # of the build dependencies;
  build-packages = fetch-sources {
    inherit packages storage-backend;
    dependencies = spagoYamlJSON.package.dependencies;
  };

  # Download the source code for each package in the transitive closure
  # of the build and test dependencies;
  test-packages = fetch-sources {
    inherit packages storage-backend;
    dependencies =
      spagoYamlJSON.package.test.dependencies
      ++ spagoYamlJSON.package.dependencies;
  };

  buildSources = build-packages.sources;
  testSources = test-packages.sources;

  compiler-version = package-set.compiler;

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
      inherit build test develop;
    };
  };
in
build
