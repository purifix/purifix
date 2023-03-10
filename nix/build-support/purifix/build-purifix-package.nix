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
, findutils
, esbuild
, withDocs ? true
}:
{ localPackages
, package-config
, backend
, backendCommand
, storage-backend
, develop-packages
}:
let
  workspace = package-config.workspace;
  yaml = package-config.yaml;
  src = package-config.repo;
  package-set-config = workspace.package_set or workspace.set;
  extra-packages = (workspace.extra_packages or { }) // localPackages;
  inherit (callPackage ./get-package-set.nix
    { inherit fromYAML purescript-registry purescript-registry-index; }
    {
      inherit package-set-config extra-packages;
      inherit (package-config) src repo;
    }) packages package-set;

  fetch-sources = callPackage ./fetch-sources.nix { };

  # Download the source code for each package in the transitive closure
  # of the build dependencies;
  build-closure = fetch-sources {
    inherit packages storage-backend;
    dependencies = yaml.package.dependencies;
  };

  # Download the source code for each package in the transitive closure
  # of the build and test dependencies;
  test-closure = fetch-sources {
    inherit packages storage-backend;
    dependencies =
      yaml.package.test.dependencies
      ++ yaml.package.dependencies;
  };

  compiler-version = package-set.compiler;
  compiler = purifix-compiler compiler-version;
  codegen = if backend == null then "js" else "corefn";


  make-pkgs = lib.makeOverridable (callPackage ./make-package-set.nix { }) {
    inherit storage-backend
      packages
      codegen
      compiler
      fetch-sources
      backendCommand
      withDocs;
  };

  top-level = {
    pname = yaml.package.name;
    version = yaml.package.version or yaml.package.publish.version;
    src = package-config.src;
    repo = package-config.repo;
    dependencies = yaml.package.dependencies;
  };
  build-pkgs = make-pkgs build-pkgs (build-closure.packages ++ [ top-level ]);

  top-level-test = top-level // {
    dependencies = yaml.package.test.dependencies ++ yaml.package.dependencies;
  };
  test-pkgs = make-pkgs test-pkgs (test-closure.packages ++ [ top-level-test ]);


  runMain = yaml.package.main or "Main";
  testMain = yaml.package.test.main or "Test.Main";

  prepareOutput = { caches, globs, copyOutput, ... }: ''
    mkdir -p output
  '' + lib.optionalString (builtins.length caches > 0) ''
    cp -r --preserve --no-clobber -t output/ ${toString copyOutput}
    chmod -R +w output
    ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
  '';

  purifix =
    let
      all-locals = builtins.attrNames localPackages;
      locals = if develop-packages == null then all-locals else develop-packages;
      all-dependencies = map (pkg: build-pkgs.${pkg}.package.dependencies) locals;
      dev-deps = builtins.filter (dep: !(builtins.elem dep all-locals)) (builtins.concatLists all-dependencies);
      package = {
        pname = "purifix-dev-shell";
        version = "0.0.0";
        src = null;
        subdir = null;
        dependencies = dev-deps;
      };
      deps-pkgs = make-pkgs deps-pkgs (build-closure.packages ++ [ package ]);
      dev-globs = map (pkg: ''''${PURIFIX_ROOT:-.}/${build-pkgs.${pkg}.package.subdir}/src/**/*.purs'') locals;
    in
    writeShellScriptBin "purifix"
      (prepareOutput
        {
          inherit (deps-pkgs.purifix-dev-shell) globs caches copyOutput;
        } + ''
        purs compile --codegen ${codegen} ${toString deps-pkgs.purifix-dev-shell.globs} "$@"
        ${backendCommand}
      '') // {
      inherit (deps-pkgs.purifix-dev-shell) globs caches copyOutput;
    };

  run = writeShellScriptBin yaml.package.name ''
    ${nodejs}/bin/node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from '${build}/output/${runMain}/index.js'; main();"
  '';

  # TODO: figure out how to run tests with other backends, js only for now
  test =
    test-pkgs.${yaml.package.name}.overrideAttrs
      (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ nodejs ];
        buildPhase = ''
          purs compile ${toString old.passthru.globs} "${old.passthru.package.src}/${old.passthru.package.subdir or ""}/test/**/*.purs"
        '';
        installPhase = ''
          node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from './output/${testMain}/index.js'; main();" | tee $out
        '';
        fixupPhase = "#nothing to be done here";
      });

  docs = { format ? "html" }:
    let
      inherit (build-pkgs.${yaml.package.name}) globs;
    in
    stdenv.mkDerivation {
      name = "${yaml.package.name}-docs";
      src = package-config.src;
      nativeBuildInputs = [
        compiler
      ];
      buildPhase = (prepareOutput build-pkgs.${yaml.package.name}) + ''
        purs docs --format ${format} ${toString globs} "$src/**/*.purs" --output docs
      '';
      installPhase = ''
        mv docs $out
      '';
    };


  develop =
    stdenv.mkDerivation {
      name = "develop-${yaml.package.name}";
      buildInputs = [
        compiler
        purescript-language-server
        purifix
      ];
      shellHook = ''
        export PURS_IDE_SOURCES='${toString purifix.globs}'
      '';
    };

  build = build-pkgs.${yaml.package.name}.overrideAttrs
    (old: {
      fixupPhase = "# don't clear output directory";
      passthru = {
        inherit build test develop bundle docs run;
        bundle-default = bundle { };
        bundle-app = bundle { app = true; };
      };
    });

  bundle =
    { minify ? false
    , format ? "iife"
    , app ? false
    , module ? runMain
    }: stdenv.mkDerivation {
      name = "bundle-${yaml.package.name}";
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
          ${command} ${moduleFile}
        '';
      installPhase = ''
        mv bundle.js $out
      '';
    };
in
build
