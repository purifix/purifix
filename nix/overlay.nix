final: prev: {


  example-purescript-package = final.purescript2nix {
    src = ../example-purescript-package;
  };


  purescript-dev-shell = final.mkShell {
    nativeBuildInputs = [
      final.dhall
      final.purescript
      final.spago
    ];
  };
}
