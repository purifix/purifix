final: prev: {

  purescript2nix = final.callPackage ./build-support/purescript2nix {};

  example-purescript-package = final.purescript2nix {
    pname = "example-purescript-package";
    version = "0.0.1";
    src = ../example-purescript-package;
  };

  purescript-dev-shell = final.mkShell {
    nativeBuildInputs = [
      final.dhall
      final.purescript
      final.spago
    ];
  };

  # dhall-nixpkgs needs to be overridden because the dhallDirectoryToNix
  # function used by purescript2nix uses the
  # `dhall-nixpkgs directory --fixed-output-derivation`
  # flag, but that flag is not available yet in the latest dhall-nixpkgs
  # release.
  dhall-nixpkgs = final.haskell.lib.justStaticExecutables (
    final.haskell.lib.overrideCabal final.haskellPackages.dhall-nixpkgs (oldAttrs: {
      src = final.stdenv.mkDerivation {
        name = "dhall-nixpkgs-src";
        src = final.fetchurl {
          # This is the latest commit from
          # https://github.com/dhall-lang/dhall-haskell/pull/2326 as of
          # 2021-11-08.
          url = "https://github.com/dhall-lang/dhall-haskell/archive/3d56794eef338962d623b55521a427cc58de88bb.tar.gz";
          sha256 = "sha256-0E6+bQV6hShHL3JmtjvSo4rGmpUFm00Jmr66csJ4bGA=";
        };
        # This derivation is a hacky way to get only the `dhall-nixpkgs/`
        # directory from the above archive.  I imagine there is probably
        # a better way to do this...
        installPhase = ''
          cp -r ./dhall-nixpkgs $out/
        '';
      };
      # some new libs have been added in this PR
      editedCabalFile = null;
      executableHaskellDepends = oldAttrs.executableHaskellDepends ++ [ final.haskellPackages.memory ];
    })
  );

}
