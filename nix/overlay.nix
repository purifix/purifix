{ purescript-registry, purescript-registry-index }: final: prev: {

  # This is the purescript2nix function.  This makes it easy to build a
  # PureScript package with Nix.  This is the main function provided by this
  # repo.
  purescript2nix = final.callPackage ./build-support/purescript2nix {
    inherit purescript-registry purescript-registry-index;
  };

}
