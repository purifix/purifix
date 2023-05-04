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
, storage-backend
, develop-packages
, backends
, withDocs
, nodeModules
, copyFiles
}:
let
  fetchPackage = callPackage ./fetch-package.nix { inherit storage-backend; };
  linkFiles = callPackage ./link-files.nix { };
  workspace = package-config.workspace;
  yaml = package-config.config;
  package-set-config = workspace.package_set or workspace.set;
  extra-packages = (workspace.extra_packages or { }) // (lib.mapAttrs (_: x: x // { isLocal = true; }) localPackages);
  inherit (callPackage ./get-package-set.nix
    { inherit fromYAML purescript-registry purescript-registry-index; }
    {
      inherit package-set-config extra-packages;
      inherit (package-config) src repo;
    }) packages package-set;

  compiler-version = package-set.compiler;
  compiler = purifix-compiler compiler-version;
  build-package = callPackage ./build-package.nix { inherit linkFiles; } {
    backend = workspace.backend or { };
    inherit
      compiler
      withDocs
      backends
      copyFiles;
  };

  make-pkgs = lib.makeOverridable (callPackage ./make-package-set.nix { inherit fetchPackage build-package; });
  pkgs = make-pkgs packages;

  runMain = yaml.package.run.main or "Main";
  testMain = yaml.package.test.main or "Test.Main";

  run =
    let evaluate = "import {main} from 'file://$out/output/${runMain}/index.js'; main();";
    in stdenv.mkDerivation {
      pname = yaml.package.name;
      version = yaml.package.version or "0.0.0";
      phases = [ "installPhase" "fixupPhase" ];
      installPhase = ''
        mkdir $out
        mkdir $out/bin
        ${lib.optionalString (nodeModules != null) "ln -s ${nodeModules} $out/node_modules"}
        cp --preserve -L -rv ${build}/output $out/output
        echo "#!${runtimeShell}" >> $out/bin/${yaml.package.name}
        echo "${nodejs}/bin/node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval=\"${evaluate}\"" >> $out/bin/${yaml.package.name}
        chmod +x $out/bin/${yaml.package.name}
      '';
    };

  # TODO: figure out how to run tests with other backends, js only for now
  test = pkgs.${yaml.package.name}.overrideAttrs
    (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ nodejs ];
      buildPhase = ''
        purs compile ${toString old.passthru.globs} "${old.passthru.package.src}/${old.passthru.package.subdir or ""}/test/**/*.purs"
      '';
      installPhase = ''
        cp -r -L output test-output
        ${lib.optionalString (nodeModules != null) "ln -s ${nodeModules} node_modules"}
        node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from './test-output/${testMain}/index.js'; main();" | tee $out
      '';
      fixupPhase = "#nothing to be done here";
    });

  docs = { format ? "html" }:
    let
      inherit (pkgs.${yaml.package.name}) globs;
    in
    stdenv.mkDerivation {
      name = "${yaml.package.name}-docs";
      src = package-config.src;
      nativeBuildInputs = [
        compiler
      ];
      buildPhase = ''
        mkdir output
        cp --no-clobber --preserve -r -L -t output ${pkgs.${yaml.package.name}.deps}/output/*
        chmod -R +w output
        purs docs --format ${format} ${toString globs} "$src/**/*.purs" --output docs
      '';
      installPhase = ''
        mv docs $out
      '';
    };


  develop = callPackage ./purifix-shell-for.nix
    {
      inherit purescript-language-server build-package;
    }
    {
      purifix-pkgs = pkgs;
      inherit compiler localPackages develop-packages;
      package = packages.${yaml.package.name};
    };

  build = pkgs.${yaml.package.name}.overrideAttrs
    (old: {
      fixupPhase = "# don't clear output directory";
      passthru = old.passthru // {
        inherit build test develop bundle docs run;
        bundle-default = bundle { };
        bundle-app = bundle { app = true; };
        package-set = pkgs;
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
