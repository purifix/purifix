{ stdenv
, callPackage
, purifix-compiler
, writeShellScriptBin
, nodejs
, lib
, fromYAML
, purescript-registry
, purescript-registry-index
, purescript-language-server
, jq
, findutils
, esbuild
}:
{
  # Source of the input purescript package. Should be a path containing a
  # spago.yaml file.
  #
  # Example: ./some/path/to/purescript-strings
  src
, storage-backend ? package: "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz"
, backends ? [ ]
, develop-packages ? null
, allowMultiWorkspaceBuild ? false
, withDocs ? true
, copyFiles ? false
, nodeModules ? null
, localPackages ? null
}:

let
  find-packages = callPackage ./find-packages.nix
    { inherit fromYAML; }
    { inherit allowMultiWorkspaceBuild src; };
  localPackages_ =
    if localPackages == null then
      builtins.listToAttrs (find-packages null [ ] src)
    else localPackages;

  build-package = callPackage ./build-purifix-package.nix {
    inherit fromYAML purescript-registry purescript-registry-index purescript-language-server;
  };
  package-names = builtins.attrNames localPackages_;
  build = name: package-config:
    build-package {
      localPackages = localPackages_;
      inherit package-config;
      inherit storage-backend develop-packages withDocs copyFiles nodeModules backends;
    };
in
if builtins.length package-names == 1 then
  let
    name = builtins.elemAt package-names 0;
    pkg = localPackages_.${name};
  in
  build name pkg
else
  let
    purescript-pkgs = builtins.mapAttrs
      (name: pkg: build name pkg // { pkgs = purescript-pkgs; })
      localPackages_;
  in
  purescript-pkgs
