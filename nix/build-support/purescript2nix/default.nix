
{ callPackage, dhallDirectoryToNix, lib, purescript, stdenv }:

# This is the main purescript2nix function.  See ../../overlay.nix for an
# example of how this can be used.

{ # Package name.  Should be a string.
  #
  # Example: "purescript-strings"
  pname
, # Package version.  Should be a string.
  #
  # Example: "1.2.3"
  version ? ""
, # Source of the input purescript package. Should be a path.
  #
  # Example: ./some/path/to/purescript-strings
  src
}:

let
  # This is the `spago.dhall` file translated to Nix.
  #
  # Example:
  #
  #   {
  #     name = "purescript-strings";
  #     dependencies = [ "console", "effect", "foldable-traversable", "prelude", "psci-support" ];
  #     packages = {
  #       abides = {
  #         dependencies = [ "enums", "foldable-traversable" ];
  #         hash = "sha256-nrZiUeIY7ciHtD4+4O5PB5GMJ+ZxAletbtOad/tXPWk=";
  #         repo = "https://github.com/athanclark/purescript-abides.git";
  #         version = "v0.0.1";
  #       };
  #       ...
  #     };
  #     sources = [ "src/**/*.purs", "test/**/*.purs" ];
  #   }
  spagoDhall = dhallDirectoryToNix { inherit src; file = "spago.dhall"; };

  # `spagoDhallDeps` is a list of all transitive dependencies of the package defined
  # in `spagoDhall`.
  #
  # In the above example, you can see that `console` is a direct dependency of
  # `purescript-strings`.  The first package in the following list is `console`.
  # This list of packages of course also contains all the transitive dependencies
  # of `console`:
  #
  # Example:
  #
  #   [
  #     {
  #       dependencies = [ "effect" "prelude" ];
  #       hash = "sha256-gh81AQOF9o1zGyUNIF8Ticqaz8Nr+pz72DOUE2wadrA=";
  #       name = "console";
  #       repo = "https://github.com/purescript/purescript-console.git";
  #       version = "v5.0.0";
  #     }
  #     ...
  #   ]
  #
  # The dependency graph is determined by figuring out the transitive
  # dependencies of `spagoDhall.dependencies` using the data in
  # `spagoDhall.packages`.
  spagoDhallDeps = import ./spagoDhallDependencyClosure.nix spagoDhall;

  purescriptPackageToFOD = callPackage ./purescriptPackageToFOD.nix {};

  # List of derivations of the `spagoDhallDeps` source code.
  spagoDhallDepDrvs = map purescriptPackageToFOD spagoDhallDeps;

  # List of globs matching the source code for each of the transitive
  # dependencies from `spagoDhallDepDrvs`.
  #
  # Example:
  #   [
  #     "\"/nix/store/1sjyzw92sxil3yp5cndhaicl55m1djal-console-v5.0.0/src/**/*.purs\""
  #     "\"/nix/store/vhshp8vh061pfnkwwcvgx6zsrq8l0v3a-effect-v3.0.0/src/**/*.purs\""
  #     ...
  #   ]
  sourceGlobs = map (dep: ''"${dep}/src/**/*.purs"'') spagoDhallDepDrvs;

  builtPureScriptCode = stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [
      purescript
    ];

    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      purs compile ${toString sourceGlobs} "$src/src/**/*.purs"
    '';
  };

in

builtPureScriptCode
