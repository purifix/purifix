{ writeShellScriptBin
, purescript-language-server
, stdenv
, lib
, build-package
}:
{ package
, compiler
, localPackages
, develop-packages
, purifix-pkgs
}:
let
  dev-shell-package = {
    pname = "purifix-dev-shell";
    version = "0.0.0";
    src = null;
    subdir = null;
    dependencies = develop-dependencies;
  };
  purifix-dev-shell = build-package purifix-pkgs dev-shell-package;

  all-locals = builtins.attrNames localPackages;
  locals = if develop-packages == null then all-locals else develop-packages;
  raw-develop-dependencies = builtins.concatLists (map (pkg: localPackages.${pkg}.config.package.dependencies) locals);
  develop-dependencies = builtins.filter (dep: !(builtins.elem dep locals)) raw-develop-dependencies;
  backendCommand = package.backend or "";
  codegen = if backendCommand == "" then "js" else "corefn";
  purifix = (writeShellScriptBin "purifix" ''
    mkdir -p output
    cp --no-clobber --preserve -r -L -t output ${purifix-dev-shell.deps}/output/*
    chmod -R +w output
    purs compile --codegen ${codegen} ${toString purifix-dev-shell.globs} "$@"
    ${backendCommand}
  '') // {
    globs = purifix-dev-shell.globs;
  };

  purifix-project =
    let
      relative = trail: lib.concatStringsSep "/" trail;
      projectGlobs = lib.mapAttrsToList (name: pkg: ''"''${PURIFIX_ROOT:-.}/${relative pkg.trail}/src/**/*.purs"'') localPackages;
    in
    writeShellScriptBin "purifix-project" ''
      purifix ${toString projectGlobs} "$@"
    '';
in
stdenv.mkDerivation {
  name = "develop-${package.name}";
  buildInputs = [
    compiler
    purescript-language-server
    purifix
    purifix-project
  ];
  shellHook = ''
    export PURS_IDE_SOURCES='${toString purifix.globs}'
  '';
}
