{}:

# Nixpkgs with overlays for purescript2nix.
# This is convenient to use with `nix repl`:
#
# $ nix repl ./nix

let
  flake-lock = builtins.fromJSON (builtins.readFile ../flake.lock);

  nixpkgs-src = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${flake-lock.nodes.nixpkgs.locked.rev}.tar.gz";
    sha256 = flake-lock.nodes.nixpkgs.locked.narHash;
  };

  overlays = [
    (import ./overlay.nix)
  ];

  pkgs = import nixpkgs-src { inherit overlays; };

in

pkgs
