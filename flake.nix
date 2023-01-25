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
        (system:
          let
            pkgs = nixpkgsFor.${system};
            fromYAML = pkgs.callPackage ./nix/build-support/purescript2nix/from-yaml.nix { };
          in
          {
            example-registry-package = pkgs.purescript2nix {
              subdir = "example-registry-package";
              src = ./.;
            };
            example-registry-package-test = (pkgs.purescript2nix {
              subdir = "example-registry-package";
              src = ./.;
            }).test;
            example-registry-package-bundle = (pkgs.purescript2nix {
              subdir = "example-registry-package";
              src = ./.;
            }).bundle {
              app = true;
              minify = true;
            };
            example-purenix-package = (pkgs.extend purenix.overlay).purescript2nix {
              src = ./example-purenix-package;
              backend = pkgs.purenix;
            };
            registry-8_6 = pkgs.callPackage ./nix/build-support/purescript2nix/test-package-set.nix { inherit fromYAML purescript-registry purescript-registry-index; } {
              package-set-config = {
                registry = "8.6.0";
              };
            };
            registry-11_1_0 = pkgs.callPackage ./nix/build-support/purescript2nix/test-package-set.nix { inherit fromYAML purescript-registry purescript-registry-index; } {
              package-set-config = {
                registry = "11.1.0";
              };
            };
            built-registry-11_1_0 = pkgs.callPackage ./nix/build-support/purescript2nix/test-package-set-built.nix { inherit fromYAML purescript-registry purescript-registry-index; } {
              package-set-config = {
                registry = "11.1.0";
              };
            };
            purenix-package-set = pkgs.callPackage ./nix/build-support/purescript2nix/test-package-set.nix { inherit fromYAML purescript-registry purescript-registry-index; } {
              package-set-config = {
                url = "https://raw.githubusercontent.com/considerate/purenix-package-sets/58722e0989beca7ae8d11495691f0684188efa8c/package-sets/0.0.1.json";
                hash = "sha256-F/7YwbybwIxvPGzTPrViF8MuBWf7ztPnNnKyyWkrEE4=";
              };
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
