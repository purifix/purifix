final: prev: {

  # This is the purescript2nix function.  This makes it easy to build a
  # PureScript package with Nix.  This is the main function provided by this
  # repo.
  purescript2nix = final.callPackage ./build-support/purescript2nix {};

  # This is an example PureScript package that has been built by the
  # purescript2nix function.
  #
  # This is just a test that purescript2nix actually works, as well an example
  # that end users can base their own code off of.
  example-purescript-package = final.purescript2nix {
    pname = "example-purescript-package";
    version = "0.0.1";
    src = ../example-purescript-package;
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
