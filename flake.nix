{
  description = "Tool for building PureScript projects with Nix";

  # This is the code from
  # https://github.com/NixOS/nixpkgs/pull/144076
  inputs.nixpkgs.url = "github:NixOS/nixpkgs?ref=dhallDirectoryToNix";

  outputs = { self, nixpkgs }:
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

    in

    {
      # A Nixpkgs overlay.  This contains the purescript2nix function that
      # end-users will want to use.
      overlay = import ./nix/overlay.nix;

      packages = forAllSystems (system: {
        # This is just an example purescript package that has been built using
        # the purescript2nix function.
        inherit (nixpkgsFor.${system}) example-purescript-package;
      });

      # defaultPackage = forAllSystems (system: self.packages.${system}.hello);

      devShells = forAllSystems (system: {
        # This purescript development shell just contains dhall, purescript,
        # and spago.  This is convenient for making changes to
        # ./example-purescript-package. But most users can ignore this.
        inherit (nixpkgsFor.${system}) purescript-dev-shell;
      });

      devShell = forAllSystems (system: self.devShells.${system}.purescript-dev-shell);
    };
}
