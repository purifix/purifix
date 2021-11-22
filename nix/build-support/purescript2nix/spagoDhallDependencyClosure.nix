
{ packages, dependencies, ... }:

let
  depToGenericClosureVal = depName:
    { key = depName; package = packages.${depName}; };

  allDeps = builtins.genericClosure {
    # startSet = [ { key = "a"; package = allDeps.a; } ];
    startSet = map depToGenericClosureVal dependencies;
    operator = { key, package }: map depToGenericClosureVal package.dependencies;
  };

  allPackages = map (dep: dep.package // { name = dep.key; }) allDeps;
in
allPackages
