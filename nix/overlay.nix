{ purescript-registry, purescript-registry-index }: final: prev: {

  # This is the purescript2nix function.  This makes it easy to build a
  # PureScript package with Nix.  This is the main function provided by this
  # repo.
  purescript2nix = final.callPackage ./build-support/purescript2nix {
    inherit purescript-registry purescript-registry-index;
  };

  example-registry-package = final.purescript2nix {
    src = ../example-registry-package;
  };

  # This is a simple develpoment shell with purescript and spago.  This can be
  # used for building the ../example-purescript-package repo using purs and
  # spago.
  purescript-dev-shell = final.mkShell {
    nativeBuildInputs = [
      final.dhall
      final.purescript
      final.spago
    ];
  };
}
