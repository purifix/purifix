{
  description = "Tool for building PureScript projects with Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  inputs.purescript-registry.url = "github:purescript/registry";
  inputs.purescript-registry.flake = false;

  inputs.purescript-registry-index.url = "github:purescript/registry-index";
  inputs.purescript-registry-index.flake = false;
  inputs.easy-purescript-nix.url = "github:justinwoo/easy-purescript-nix";
  inputs.easy-purescript-nix.flake = false;

  inputs.purenix.url = "github:purenix-org/purenix";

  outputs =
    { self
    , nixpkgs
    , purescript-registry
    , purescript-registry-index
    , easy-purescript-nix
    , purenix
    }:
    let
      # System types to support.
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
      ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });

      # This is a simple develpoment shell with purescript and spago.  This can be
      # used for building the ../example-purescript-package repo using purs and
      # spago.

    in

    {
      # A Nixpkgs overlay.  This contains the purescript2nix function that
      # end-users will want to use.
      overlay = import ./nix/overlay.nix {
        inherit purescript-registry purescript-registry-index easy-purescript-nix;
      };

      packages = forAllSystems
        (system: {
          example-registry-package = nixpkgsFor.${system}.purescript2nix {
            subdir = "example-registry-package";
            src = ./.;
          };
          example-registry-package-test = (nixpkgsFor.${system}.purescript2nix {
            subdir = "example-registry-package";
            src = ./.;
          }).test;
          example-purenix-package =
            let
              pkgs = nixpkgsFor.${system}.extend purenix.overlay;
            in
            pkgs.purescript2nix {
              src = ./example-purenix-package;
              backend = pkgs.purenix;
            };
        });

      # defaultPackage = forAllSystems (system: self.packages.${system}.hello);

      devShells = forAllSystems (system: {
        # This purescript development shell just contains dhall, purescript,
        # and spago.  This is convenient for making changes to
        # ./example-purescript-package. But most users can ignore this.
        purescript-dev-shell = (nixpkgsFor.${system}.purescript2nix {
          subdir = "example-registry-package";
          src = ./.;
        }).develop;
      });

      devShell = forAllSystems (system: self.devShells.${system}.purescript-dev-shell);
    };
}
