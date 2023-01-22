{ purescript-registry, purescript-registry-index, easy-purescript-nix }: final: prev:
let
  easy-ps = import easy-purescript-nix {
    pkgs = final;
  };
  fromYAML = final.callPackage ./build-support/purescript2nix/from-yaml.nix { };
in
{

  # This function selects the purescript compiler to use when building in purescript2nix based on the requested compiler version.
  purescript2nix-compiler = final.callPackage ./build-support/purescript2nix/get-compiler-by-version.nix {
    inherit easy-ps;
  };
  # This is the purescript2nix function.  This makes it easy to build a
  # PureScript package with Nix.  This is the main function provided by this
  # repo.
  purescript2nix = final.callPackage ./build-support/purescript2nix {
    inherit purescript-registry purescript-registry-index fromYAML;
  };

}
