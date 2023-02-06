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
            package-sets = pkgs.lib.filter (v: pkgs.lib.stringLength v > 0) (pkgs.lib.splitString "\n" (builtins.readFile ./package-sets.txt));
            registry-package-sets = builtins.listToAttrs (map
              (registry-version:
                let
                  parts = pkgs.lib.splitVersion registry-version;
                  major = builtins.elemAt parts 0;
                  minor = builtins.elemAt parts 1;
                  patch = builtins.elemAt parts 2;
                in
                {
                  name = "registry-${major}_${minor}_${patch}";
                  value = pkgs.callPackage ./nix/build-support/purescript2nix/build-package-set.nix { inherit fromYAML purescript-registry purescript-registry-index; } {
                    package-set-config = {
                      registry = registry-version;
                    };
                  };
                })
              package-sets);
            all-package-sets = pkgs.linkFarm "purescript2nix-package-sets" (pkgs.lib.mapAttrsToList (name: path: { inherit name path; }) registry-package-sets);
            example-registry-package = pkgs.purescript2nix {
              subdir = "example-registry-package";
              src = ./examples;
            };
            nonincremental-package = pkgs.purescript2nix {
              subdir = "example-registry-package";
              src = ./examples;
              incremental = false;
            };
          in
          registry-package-sets // {
            inherit all-package-sets;
          } // {
            inherit example-registry-package;
            conflict = pkgs.purescript2nix {
              src = ./examples;
              subdir = "top-level-conflict";
            };
            conflict-a = pkgs.purescript2nix {
              src = ./examples;
              subdir = "dependency-conflict";
            };
            conflict-b = pkgs.purescript2nix {
              src = ./examples;
              subdir = "dependency-conflict-b";
            };
            example-registry-package-test = example-registry-package.test;
            example-registry-package-bundle = example-registry-package.bundle {
              app = true;
              minify = true;
            };
            example-registry-package-docs = example-registry-package.docs { };
            inherit nonincremental-package;
            nonincremental-package-test = nonincremental-package.test;
            nonincremental-package-bundle = nonincremental-package.bundle {
              app = true;
              minify = true;
            };
            nonincremental-package-docs = nonincremental-package.docs { format = "markdown"; };
            example-purenix-package = (pkgs.extend purenix.overlay).purescript2nix {
              src = ./examples/example-purenix-package;
              backend = pkgs.purenix;
            };
            purenix-package-set = pkgs.callPackage ./nix/build-support/purescript2nix/build-package-set.nix { inherit fromYAML purescript-registry purescript-registry-index; } {
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
          src = ./examples;
        }).develop;
        spago =
          let
            pkgs = nixpkgsFor.${system};
            easy-ps = import easy-purescript-nix {
              pkgs = pkgs;
            };
          in
          pkgs.mkShell {
            name = "spago-shell";
            buildInputs = [ easy-ps.spago easy-ps.purs-0_15_7 ];
          };
      });

      devShell = forAllSystems (system: self.devShells.${system}.purescript-dev-shell);
    };
}
