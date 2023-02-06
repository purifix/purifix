{ stdenv
, callPackage
, purescript2nix-compiler
, writeShellScriptBin
, nodejs
, lib
, fromYAML
, purescript-registry
, purescript-registry-index
, linkFarm
, jq
}:
{ package-set-config
, extra-packages ? { }
, storage-backend ? package: "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz"
, backend ? null
, backendCommand ? lib.optionalString (backend != null) "${backend}/bin/${backend.pname}"
}:
let
  inherit
    (callPackage ./get-package-set.nix
      { inherit fromYAML purescript-registry purescript-registry-index; }
      { inherit package-set-config extra-packages; })
    packages
    package-set;
  fetch-sources = callPackage ./fetch-sources.nix { };
  compiler = purescript2nix-compiler package-set.compiler;
  codegen = if backend == null then "js" else "corefn";
  closure = fetch-sources {
    inherit packages storage-backend;
    dependencies = builtins.attrNames packages;
  };
  make-pkgs = callPackage ./make-package-set.nix { } {
    inherit storage-backend
      packages
      codegen
      compiler
      fetch-sources
      backendCommand;
    withDocs = false;
  };
  pkgs = make-pkgs pkgs closure.packages;
  paths = lib.mapAttrsToList (name: path: { inherit name path; }) pkgs;
  package-set-version =
    if builtins.hasAttr "registry" package-set-config
    then package-set-config.registry
    else package-set-config.git or "unknown";
in
linkFarm "purescript-registry-${package-set-version}" paths
