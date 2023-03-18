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
, runtimeShell
}:
{ localPackages
, package-config
, backend
, backendCommand
, storage-backend
, develop-packages
, withDocs
, nodeModules
}:
let
  workspace = package-config.workspace;
  yaml = package-config.config;
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

  all-locals = builtins.attrNames localPackages;
  locals = if develop-packages == null then all-locals else develop-packages;
  raw-develop-dependencies = builtins.concatLists (map (pkg: localPackages.${pkg}.config.package.dependencies) locals);
  develop-dependencies = builtins.filter (dep: !(builtins.elem dep locals)) raw-develop-dependencies;
  develop-closure = fetch-sources {
    inherit packages storage-backend;
    dependencies = develop-dependencies;
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

  top-level = pkg: {
    pname = pkg.config.package.name;
    version = pkg.config.package.version or pkg.config.package.publish.version;
    src = pkg.src;
    repo = pkg.repo;
    dependencies = pkg.config.package.dependencies;
  };
  build-pkgs = make-pkgs build-pkgs (build-closure.packages ++ map top-level (builtins.attrValues localPackages));

  top-level-test = pkg: top-level pkg // {
    dependencies = pkg.config.package.test.dependencies ++ pkg.config.package.dependencies;
  };
  test-pkgs = make-pkgs test-pkgs (test-closure.packages ++ map top-level-test (builtins.attrValues localPackages));

  dev-shell-package = {
    pname = "purifix-dev-shell";
    version = "0.0.0";
    src = null;
    subdir = null;
    dependencies = develop-dependencies;
  };
  dev-pkgs = make-pkgs dev-pkgs (develop-closure.packages ++ [ dev-shell-package ]);

  runMain = yaml.package.run.main or "Main";
  testMain = yaml.package.test.main or "Test.Main";

  prepareOutput = { caches, globs, copyOutput, ... }: ''
    mkdir -p output
  '' + lib.optionalString (builtins.length caches > 0) ''
    cp -r --preserve --no-clobber -t output/ ${toString copyOutput}
    chmod -R +w output
    ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
  '';

  purifix =
    writeShellScriptBin "purifix"
      (prepareOutput
        {
          inherit (dev-pkgs.purifix-dev-shell) globs caches copyOutput;
        } + ''
        purs compile --codegen ${codegen} ${toString dev-pkgs.purifix-dev-shell.globs} "$@"
        ${backendCommand}
      '') // {
      inherit (dev-pkgs.purifix-dev-shell) globs caches copyOutput;
    };

  run =
    let evaluate = "import {main} from 'file://$out/output/${runMain}/index.js'; main();";
    in stdenv.mkDerivation {
      pname = yaml.package.name;
      version = yaml.package.version or "0.0.0";
      phases = [ "installPhase" "fixupPhase" ];
      installPhase = ''
        mkdir $out
        mkdir $out/bin
      '' + lib.optionalString (nodeModules != null) ''
        ln -s ${nodeModules} $out/node_modules
      '' +
      ''
        cp -rv ${build}/output $out/output
        echo "#!${runtimeShell}" >> $out/bin/${yaml.package.name}
        echo "${nodejs}/bin/node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval=\"${evaluate}\"" >> $out/bin/${yaml.package.name}
        chmod +x $out/bin/${yaml.package.name}
      '';
    };

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
