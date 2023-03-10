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
      # A Nixpkgs overlay.  This contains the purifix function that
      # end-users will want to use.
      overlay = import ./nix/overlay.nix {
        inherit purescript-registry purescript-registry-index easy-purescript-nix;
      };

      packages = forAllSystems
        (system:
          let
            pkgs = nixpkgsFor.${system};
            fromYAML = pkgs.callPackage ./nix/build-support/purifix/from-yaml.nix { };
            package-sets = builtins.attrNames (builtins.readDir (purescript-registry + "/package-sets"));
            package-set-versions-raw = map
              (registry-file:
                let
                  registry-version = nixpkgs.lib.removeSuffix ".json" registry-file;
                  parts = nixpkgs.lib.splitVersion registry-version;
                  major = builtins.elemAt parts 0;
                  minor = builtins.elemAt parts 1;
                  patch = builtins.elemAt parts 2;
                in
                { inherit registry-version major minor patch; }
              )
              package-sets;
            bad-package-sets = [
              "14.2.0" # jelly fails to compile
            ];
            package-set-versions = builtins.filter ({ registry-version, ... }: !(builtins.elem registry-version bad-package-sets)) package-set-versions-raw;
            recent-package-set-versions = nixpkgs.lib.filter ({ registry-version, ... }: nixpkgs.lib.versionAtLeast registry-version "12.0.0") package-set-versions;
            to-package-set = { registry-version, major, minor, patch }:
              {
                name = "registry-${major}_${minor}_${patch}";
                value = pkgs.callPackage ./nix/build-support/purifix/build-package-set.nix { inherit fromYAML purescript-registry purescript-registry-index; } {
                  package-set-config = {
                    registry = registry-version;
                  };
                };
              };
            registry-package-sets = builtins.listToAttrs (map to-package-set package-set-versions);
            recent-registry-package-sets = builtins.listToAttrs (map to-package-set recent-package-set-versions);
            all-package-sets = pkgs.linkFarm "purifix-package-sets" (nixpkgs.lib.mapAttrsToList (name: path: { inherit name path; }) registry-package-sets);
            new-package-sets = pkgs.linkFarm "recent-purifix-package-sets" (nixpkgs.lib.mapAttrsToList (name: path: { inherit name path; }) recent-registry-package-sets);
            example-registry-package = (pkgs.purifix {
              src = ./examples;
            }).example-purescript-package;
          in
          registry-package-sets // {
            inherit all-package-sets new-package-sets;
          } // {
            inherit example-registry-package;
            conflict = pkgs.purifix {
              src = ./examples;
              subdir = "top-level-conflict";
            };
            conflict-a = pkgs.purifix {
              src = ./examples;
              subdir = "dependency-conflict";
            };
            conflict-b = pkgs.purifix {
              src = ./examples;
              subdir = "dependency-conflict-b";
            };
            example-registry-package-test = example-registry-package.test;
            example-registry-package-run = example-registry-package.run;
            example-registry-package-bundle = example-registry-package.bundle {
              app = true;
              minify = true;
            };
            example-registry-package-docs = example-registry-package.docs { };
            example-purenix-package = (pkgs.extend purenix.overlay).purifix {
              src = ./examples/example-purenix-package;
              backend = pkgs.purenix;
            };
            remote-monorepo = pkgs.purifix {
              src = ./examples/remote-monorepo;
            };
            purenix-package-set = pkgs.callPackage ./nix/build-support/purifix/build-package-set.nix { inherit fromYAML purescript-registry purescript-registry-index; } {
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
        purescript-dev-shell = (nixpkgsFor.${system}.purifix {
          src = ./examples;
          develop-packages = [ "example-purescript-package" "example-dependency" ];
        }).example-purescript-package.develop;
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
