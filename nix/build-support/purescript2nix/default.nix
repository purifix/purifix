{ stdenv
, callPackage
, purescript2nix-compiler
, writeShellScriptBin
, nodejs
, lib
, fromYAML
, purescript-registry
, purescript-registry-index
, jq
, esbuild
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
  compiler = purescript2nix-compiler compiler-version;
  codegen = if backend == null then "js" else "corefn";

  make-pkgs = final: inputs:
    let
      build-package = package:
        let
          copyOutput = map (dep: let pkg = final.${dep}; in ''${pkg}/output/*'') package.dependencies;
          dependency-closure = fetch-sources {
            inherit packages storage-backend;
            dependencies = package.dependencies;
          };
          caches = map (dep: let pkg = final.${dep}; in ''${pkg}/output/cache-db.json'') package.dependencies;
          globs = map (dep: ''"${dep.src}/${dep.subdir or ""}/src/**/*.purs"'') dependency-closure.packages;
          value = stdenv.mkDerivation {
            pname = package.pname;
            version = package.version or "0.0.0";
            phases = [ "preparePhase" "buildPhase" "installPhase" ];
            nativeBuildInputs = [
              compiler
            ];
            preparePhase = ''
              mkdir -p output
            '' + lib.optionalString (builtins.length package.dependencies > 0) ''
              cp -r --preserve --no-clobber -t output/ ${toString copyOutput}
              chmod -R +w output
              ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
            '';
            buildPhase = ''
              purs compile --codegen ${codegen} ${toString globs} "${package.src}/${package.subdir or ""}/src/**/*.purs"
              ${backendCommand}
            '';
            installPhase = ''
              mkdir -p "$out"
              cp -r output "$out/"
            '';
            passthru = {
              inherit globs caches copyOutput;
              inherit package;
            };
          };
        in
        {
          name = package.pname;
          value = value;
        };
    in
    builtins.listToAttrs (map build-package inputs);

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

  buildSources = build-closure.sources;
  testSources = test-closure.sources;


  testSourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') testSources;
  buildSourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') buildSources;


  testMain = spagoYamlJSON.package.test.main or "Test.Main";

  purescript-compile =
    if incremental then
      let
        inherit (build-pkgs.${spagoYamlJSON.package.name}) package caches globs copyOutput;
      in
      writeShellScriptBin "purescript-compile" (''
        mkdir -p output
      '' + lib.optionalString (builtins.length package.dependencies > 0) ''
        cp -r --preserve --no-clobber -t output/ ${toString copyOutput}
        chmod -R +w output
        ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
      '' + ''
        purs compile --codegen ${codegen} ${toString globs} "$@"
        ${backendCommand}
      '')
    else
      writeShellScriptBin "purescript-compile" ''
        purs compile --codegen ${codegen} ${toString buildSourceGlobs} "$@"
        ${backendCommand}
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

  develop = stdenv.mkDerivation {
    name = "develop-${spagoYamlJSON.package.name}";
    buildInputs = [
      compiler
      purescript-compile
    ];
  };

  bundle =
    { minify ? false
    , format ? "iife"
    , app ? false
    }: stdenv.mkDerivation {
      name = "bundle-${spagoYamlJSON.package.name}";
      phases = [ "buildPhase" "installPhase" ];
      nativeBuildInputs = [ esbuild ];
      # TODO: make module configurable
      buildPhase =
        let
          minification = lib.optionalString minify "--minify";
          module = "${build-pkgs.${spagoYamlJSON.package.name}}/output/Main/index.js";
          command = "esbuild --bundle --outfile=bundle.js --format=${format}";
        in
        if app
        then ''
          echo "import {main} from '${module}'; main()" | ${command} ${minification}
        ''
        else ''
          ${command} ${module}
        '';
      installPhase = ''
        mv bundle.js $out
      '';
    };

  build =
    if incremental
    then
      build-pkgs.${spagoYamlJSON.package.name}.overrideAttrs
        (old: {
          passthru = {
            inherit build test develop bundle;
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
          inherit build test develop;
        };
      };
in
build
