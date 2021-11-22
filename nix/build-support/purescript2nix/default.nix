
{ callPackage, dhallDirectoryToNix, lib, purescript, stdenv }:

{
  pname
, version ? ""
, src
}:

let
  spagoDhall = dhallDirectoryToNix { inherit src; file = "spago.dhall"; };

  spagoDhallDeps = import ./spagoDhallDependencyClosure.nix spagoDhall;

  purescriptPackageToFOD = callPackage ./purescriptPackageToFOD.nix {};

  spagoDhallDepDrvs = map purescriptPackageToFOD spagoDhallDeps;

  sourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') spagoDhallDepDrvs;

  builtPureScriptCode = stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [
      purescript
    ];

    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      purs compile ${toString sourceGlobs} "$src/src/**/*.purs"
    '';
  };

in

builtPureScriptCode
