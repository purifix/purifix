{ stdenv
, callPackage
, purescript2nix-compiler
, writeShellScriptBin
, nodejs
, lib
, fromYAML
, purescript-registry
, purescript-registry-index
, linkFarm
}:
{ package-set-config
, extra-packages ? { }
, storage-backend ? package: "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz"
, backend ? null
, backendCommand ? lib.optionalString (backend != null) "${backend}/bin/${backend.pname}"
}:
let
  inherit
    (callPackage ./get-package-set.nix
      { inherit fromYAML purescript-registry purescript-registry-index; }
      { inherit package-set-config extra-packages; })
    packages
    package-set;
  fetch-sources = callPackage ./fetch-sources.nix { };
  compiler = purescript2nix-compiler package-set.compiler;
  codegen = if backend == null then "js" else "corefn";
  build-package = name: package:
    let
      closure = fetch-sources {
        inherit packages storage-backend;
        dependencies = [ name ] ++ package.dependencies;
      };
      sources = closure.sources;
      globs = map (dep: ''"${dep}/src/**/*.purs"'') sources;
    in
    stdenv.mkDerivation {
      pname = name;
      version = package.version or "0.0.0";
      phases = [ "buildPhase" "installPhase" ];
      nativeBuildInputs = [
        compiler
      ];
      buildPhase = ''
        purs compile --codegen ${codegen} ${toString globs} "$src/src/**/*.purs"
        ${backendCommand}
      '';
      installPhase = ''
        mkdir -p "$out"
        cp -r output "$out/"
      '';
    };
  pkgs = builtins.mapAttrs build-package packages;
  paths = lib.mapAttrsToList (name: path: { inherit name path; }) pkgs;
in
linkFarm "package-set" paths
