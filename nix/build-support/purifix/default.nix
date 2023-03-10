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
, withDocs ? true
}:
{
  # Source of the input purescript package. Should be a path containing a
  # spago.yaml file.
  #
  # Example: ./some/path/to/purescript-strings
  src
, workspaceYaml ? "${src}/spago.yaml"
, backend ? null
, backendCommand ? lib.optionalString (backend != null) "${backend}/bin/${backend.pname}"
, storage-backend ? package: "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz"
, develop-packages ? null
}:

let

  # Parse the workspace global spago.yaml
  workspace = (fromYAML (builtins.readFile workspaceYaml)).workspace;
  # Find and parse the spago.yaml package files into nix
  # TODO: Support the purs.json file instead/as well? It doesn't seem to
  # support extra_packages but could be ok if there's a global workspace spago.yaml.
  find-candidate-packages = stdenv.mkDerivation {
    name = "purifix-find-packages";
    phases = [ "buildPhase" ];
    nativeBuildInputs = [ findutils ];
    buildPhase = ''
      find ${src} -name 'spago.yaml' | xargs dirname | tee $out
    '';
  };
  candidate-packages = builtins.readFile find-candidate-packages;
  candidate-package-json =
    let
      lines = lib.splitString "\n" candidate-packages;
      non-empty = builtins.filter (p: p != "") lines;
      yamls = map
        (dir:
          let
            yamlPath = dir + "/spago.yaml";
            yaml = fromYAML (builtins.readFile yamlPath);
          in
          {
            repo = src;
            src = dir;
            yamlPath = yamlPath;
            yaml = yaml;
            workspace = yaml.workspace or workspace;
          })
        non-empty;
      is-package = obj: builtins.hasAttr "package" obj.yaml;
      ps = builtins.filter is-package yamls;
      named = builtins.listToAttrs (map (p: { name = p.yaml.package.name; value = p; }) ps);
    in
    named;

  build-package = callPackage ./build-purifix-package.nix {
    inherit fromYAML purescript-registry purescript-registry-index purescript-language-server;
  };
  package-names = builtins.attrNames candidate-package-json;
  build = name: package-config: build-package {
    localPackages = candidate-package-json;
    package-config = package-config;
    inherit backend backendCommand storage-backend develop-packages;
  };
in
if builtins.length package-names == 1 then
  let
    name = builtins.elemAt package-names 0;
    pkg = candidate-package-json.${name};
  in
  build name pkg
else
  let purescript-pkgs = builtins.mapAttrs (name: pkg: build name pkg // { pkgs = purescript-pkgs; }) candidate-package-json;
  in purescript-pkgs
