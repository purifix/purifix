# Figure out the transitive dependencies for a PureScript package.

{ # The whole PureScript package set with all dependencies defined.
  # This should be an attribute set where keys are package names,
  # and values are attribute sets with an attribute called `dependencies`.
  #
  # Example:
  #   {
  #     abides = {
  #       dependencies = [ "enums", "foldable-traversable" ];
  #       hash = "sha256-nrZiUeIY7ciHtD4+4O5PB5GMJ+ZxAletbtOad/tXPWk=";
  #       repo = "https://github.com/athanclark/purescript-abides.git";
  #       version = "v0.0.1";
  #     };
  #     ...
  #   };
  packages
, # Starting dependency set for this package.  Should be a list of strings.
  #
  # Example: [ "console", "effect", "foldable-traversable", "prelude", "psci-support" ]
  dependencies
,
...
}:

let
  # Translate a dependency to a value to pass to
  # `builtins.genericClosure.operator`.
  #
  # depToGenericClosureVal :: String -> AttrSet
  #
  # The input string should be a string corresponding to a package in
  # `packages`.
  #
  # Example:
  #   nix-repl> depToGenericClosureVal "abides"
  #   { key = "abides"; package = { dependencies = [ "enums", "foldable-traversable" ]; ... }; }
  depToGenericClosureVal = depName:
    { key = depName; package = packages.${depName}; };

  # A list of all transitive dependencies of the `dependencies` list, in a
  # format output from `depToGenericClosureVal`.
  #
  # Example:
  #   [
  #     {
  #       key = "console";
  #       package = {
  #         dependencies = [ "effect" "prelude" ];
  #         hash = "sha256-gh81AQOF9o1zGyUNIF8Ticqaz8Nr+pz72DOUE2wadrA=";
  #         repo = "https://github.com/purescript/purescript-console.git";
  #         version = "v5.0.0";
  #       };
  #     }
  #     ...
  #   ]
  allDeps = builtins.genericClosure {
    startSet = map depToGenericClosureVal dependencies;
    operator = { key, package }: map depToGenericClosureVal package.dependencies;
  };

  # Map `allDeps` to be in a simpler shape:
  #
  # Example:
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
  allPackages = map (dep: dep.package // { name = dep.key; }) allDeps;
in
allPackages
