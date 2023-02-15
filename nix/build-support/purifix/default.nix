{ stdenv
, callPackage
, purifix-compiler
, writeShellScriptBin
, nodejs
, lib
, fromYAML
, purescript-registry
, purescript-registry-index
, purescript-language-server
, jq
, esbuild
, withDocs ? true
}:
{
  # Source of the input purescript package. Should be a path containing a
  # spago.yaml file.
  #
  # Example: ./some/path/to/purescript-strings
  src
, incremental ? true
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
  build-closure = fetch-sources {
    inherit packages storage-backend;
    dependencies = spagoYamlJSON.package.dependencies;
  };

  # Download the source code for each package in the transitive closure
  # of the build and test dependencies;
  test-closure = fetch-sources {
    inherit packages storage-backend;
    dependencies =
      spagoYamlJSON.package.test.dependencies
      ++ spagoYamlJSON.package.dependencies;
  };

  compiler-version = package-set.compiler;
  compiler = purifix-compiler compiler-version;
  codegen = if backend == null then "js" else "corefn";


  make-pkgs = callPackage ./make-package-set.nix { } {
    inherit storage-backend
      packages
      codegen
      compiler
      fetch-sources
      backendCommand
      withDocs;
  };

  build-pkgs = make-pkgs build-pkgs (build-closure.packages ++ [{
    pname = spagoYamlJSON.package.name;
    version = spagoYamlJSON.package.version;
    src = src;
    subdir = subdir;
    dependencies = spagoYamlJSON.package.dependencies;
  }]);

  test-pkgs = make-pkgs test-pkgs (test-closure.packages ++ [{
    pname = spagoYamlJSON.package.name;
    version = spagoYamlJSON.package.version;
    src = src;
    subdir = subdir;
    dependencies = spagoYamlJSON.package.test.dependencies ++ spagoYamlJSON.package.dependencies;
  }]);


  buildSourceGlobs = map (dep: ''"${dep.src}/${dep.subdir or ""}/src/**/*.purs"'') build-closure.packages;
  testSourceGlobs = map (dep: ''"${dep.src}/${dep.subdir or ""}/src/**/*.purs"'') test-closure.packages;


  runMain = spagoYamlJSON.package.main or "Main";
  testMain = spagoYamlJSON.package.test.main or "Test.Main";

  prepareOutput = { package, caches, globs, copyOutput, ... }: ''
    mkdir -p output
  '' + lib.optionalString (builtins.length package.dependencies > 0) ''
    cp -r --preserve --no-clobber -t output/ ${toString copyOutput}
    chmod -R +w output
    ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
  '';

  purifix =
    let
      inherit (build-pkgs.${spagoYamlJSON.package.name}) globs;
    in
    if incremental then
      writeShellScriptBin "purifix"
        (prepareOutput build-pkgs.${spagoYamlJSON.package.name} + ''
          purs compile --codegen ${codegen} ${toString globs} "$@"
          ${backendCommand}
        '')
    else
      writeShellScriptBin "purifix" ''
        purs compile --codegen ${codegen} ${toString buildSourceGlobs} "$@"
        ${backendCommand}
      '';

  run = writeShellScriptBin spagoYamlJSON.package.name ''
    ${nodejs}/bin/node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from '${build}/output/${runMain}/index.js'; main();"
  '';

  # TODO: figure out how to run tests with other backends, js only for now
  test =
    if incremental
    then
      test-pkgs.${spagoYamlJSON.package.name}.overrideAttrs
        (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ nodejs ];
          buildPhase = ''
            purs compile ${toString old.passthru.globs} "${old.passthru.package.src}/${old.passthru.package.subdir or ""}/test/**/*.purs"
          '';
          installPhase = ''
            node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from './output/${testMain}/index.js'; main();" | tee $out
          '';
        })
    else
      stdenv.mkDerivation {
        name = "test-${spagoYamlJSON.package.name}";
        src = src + "/${subdir}";
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

  docs = { format ? "html" }:
    if incremental
    then
      let
        inherit (build-pkgs.${spagoYamlJSON.package.name}) globs;
      in
      stdenv.mkDerivation {
        name = "${spagoYamlJSON.package.name}-docs";
        src = src + "/${subdir}";
        nativeBuildInputs = [
          compiler
        ];
        buildPhase = (prepareOutput build-pkgs.${spagoYamlJSON.package.name}) + ''
          purs docs --format ${format} ${toString globs} "$src/**/*.purs" --output docs
        '';
        installPhase = ''
          mv docs $out
        '';
      }
    else
      stdenv.mkDerivation {
        name = "${spagoYamlJSON.package.name}-docs";
        src = src + "/${subdir}";
        nativeBuildInputs = [
          compiler
        ];
        buildPhase = ''
          purs docs --format ${format} ${toString buildSourceGlobs} "$src/src/**/*.purs" --output docs
        '';
        installPhase = ''
          mv docs $out
        '';
      };


  develop =
    stdenv.mkDerivation {
      name = "develop-${spagoYamlJSON.package.name}";
      buildInputs = [
        compiler
        purifix
        purescript-language-server
      ];
      shellHook = ''
        export PURS_IDE_SOURCES='${toString buildSourceGlobs}'
      '';
    };

  build =
    if incremental
    then
      build-pkgs.${spagoYamlJSON.package.name}.overrideAttrs
        (old: {
          passthru = {
            inherit build test develop bundle docs run;
          };
        })
    else
      stdenv.mkDerivation {
        pname = spagoYamlJSON.package.name;
        version = spagoYamlJSON.package.version;

        src = src + "/${subdir}";

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
          inherit build bundle develop test docs;
        };
      };

  bundle =
    { minify ? false
    , format ? "iife"
    , app ? false
    , module ? runMain
    }: stdenv.mkDerivation {
      name = "bundle-${spagoYamlJSON.package.name}";
      phases = [ "buildPhase" "installPhase" ];
      nativeBuildInputs = [ esbuild ];
      buildPhase =
        let
          minification = lib.optionalString minify "--minify";
          moduleFile = "${build}/output/${module}/index.js";
          command = "esbuild --bundle --outfile=bundle.js --format=${format}";
        in
        if app
        then ''
          echo "import {main} from '${moduleFile}'; main()" | ${command} ${minification}
        ''
        else ''
          ${command} ${module}
        '';
      installPhase = ''
        mv bundle.js $out
      '';
    };
in
build
