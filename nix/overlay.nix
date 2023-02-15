{ purescript-registry, purescript-registry-index, easy-purescript-nix }: final: prev:
let
  easy-ps = import easy-purescript-nix {
    pkgs = final;
  };
  fromYAML = final.callPackage ./build-support/purifix/from-yaml.nix { };
in
{

  # This function selects the purescript compiler to use when building in purifix based on the requested compiler version.
  purifix-compiler = final.callPackage ./build-support/purifix/get-compiler-by-version.nix {
    inherit easy-ps;
  };
  # This is the purifix function.  This makes it easy to build a
  # PureScript package with Nix.  This is the main function provided by this
  # repo.
  purifix = final.callPackage ./build-support/purifix {
    inherit purescript-registry purescript-registry-index fromYAML;
    inherit (easy-ps) purescript-language-server;
  };

}
