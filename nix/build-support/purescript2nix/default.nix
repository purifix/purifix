
{ dhallDirectoryToNix, purescript, spago, stdenv }:

{
  pname
, version ? ""
, src
}:

let
  spagoDhall = dhallDirectoryToNix { inherit src; file = "spago.dhall"; };

  builtPureScriptCode = stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [
      purescript
      spago
    ];

    buildPhase = ''
      export HOME="$TMP"
      set -x
      pwd
      ls
      spago --global-cache skip --verbose build --no-install
    '';
  };

in

builtPureScriptCode
