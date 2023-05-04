{ writeShellScriptBin
, purescript-language-server
, stdenv
, lib
}:
{ package
, compiler
, purifix-dev-shell
, localPackages
}:
let
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
