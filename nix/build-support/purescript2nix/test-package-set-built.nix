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
    # dependencies = [ "safe-coerce" ];
    dependencies = builtins.attrNames packages;
  };
  pkgs = builtins.listToAttrs (
    map
      (package:
        let
          copyOutput = map (dep: let pkg = pkgs.${dep}; in ''${pkg}/output/*'') package.dependencies;
          dependency-closure = fetch-sources {
            inherit packages storage-backend;
            dependencies = package.dependencies;
          };
          caches = map (dep: let pkg = pkgs.${dep}; in ''${pkg}/output/cache-db.json'') package.dependencies;
          globs = map (dep: ''"${dep}/src/**/*.purs"'') dependency-closure.sources;
          value = stdenv.mkDerivation {
            pname = package.pname;
            version = package.version or "0.0.0";
            phases = [ "unpackPhase" "preparePhase" "buildPhase" "installPhase" ];
            src = package.src;
            nativeBuildInputs = [
              compiler
            ];
            preparePhase = ''
              mkdir -p output
            '' + lib.optionalString (builtins.length package.dependencies > 0) ''
              cp -r --preserve --no-clobber -t output/ ${toString copyOutput}
              chmod -R +w output
              ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
            '';
            buildPhase = ''
              purs compile --codegen ${codegen} ${toString globs} "$src/src/**/*.purs"
              ${backendCommand}
            '';
            installPhase = ''
              mkdir -p "$out"
              cp -r output "$out/"
            '';
          };
        in
        {
          name = package.pname;
          value = value;
        })
      closure.packages);
  paths = lib.mapAttrsToList (name: path: { inherit name path; }) pkgs;
in
linkFarm "package-set" paths
