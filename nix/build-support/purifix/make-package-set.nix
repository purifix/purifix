{ jq, stdenv, lib, python3, writeText, linkFiles }:
let
  # TODO: remove python dependency due to this script
  # This script will load the cache-db.json from the output folder and remove
  # all keys present in the dependencies' cache-db files. This results in that
  # each package only stores the modules that are defined in that package in
  # its cache-db.json
  reduce-cache-db = writeText "cache-db.py" ''
    import json
    import sys


    with open(sys.argv[1]) as f:
      obj = json.load(f)
    for filename in sys.argv[2:]:
      with open(filename) as f:
        x = json.load(f)
      for key in x.keys():
        del obj[key]
    print(json.dumps(obj))
  '';
in
{ storage-backend
, packages
, codegen
, compiler
, fetch-sources
, backendCommand
, withDocs ? true
, filterPackages ? (pkg: true)
}: final: inputs:
let
  build-package = package:
    let
      get-dep = dep: final.${dep};
      directs = builtins.listToAttrs (map (name: { name = name; value = get-dep name; }) package.dependencies);
      transitive = builtins.foldl' (a: pkg: a // final.${pkg}.dependencies) { } package.dependencies;
      dependencies = transitive // directs;
      deps = builtins.attrNames dependencies;
      copyOutput = map (dep: ''${get-dep dep}/output/*'') (builtins.filter filterPackages deps);
      caches = map (dep: ''${get-dep dep}/output/cache-db.json'') (builtins.filter filterPackages deps);
      globs = map (dep: ''"${(get-dep dep).package.src}/src/**/*.purs"'') (builtins.filter filterPackages deps);
      value = stdenv.mkDerivation {
        pname = package.pname;
        version = package.version or "0.0.0";
        phases = [ "preparePhase" "buildPhase" "installPhase" "fixupPhase" ];
        nativeBuildInputs = [
          compiler
        ];
        preparePhase = ''
          mkdir -p output
        '' + lib.optionalString (builtins.length package.dependencies > 0) ''
          echo ${toString copyOutput} | xargs ${linkFiles}
          chmod -R +w output
          rm output/cache-db.json
          rm output/package.json
          ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
        '';
        buildPhase = ''
          purs compile --codegen "${codegen}${lib.optionalString withDocs ",docs"}" ${toString globs} "${package.src}/src/**/*.purs"
          ${backendCommand}
        '';
        installPhase = ''
          mkdir -p "$out"
          mv output "$out/"
        '';
        fixupPhase = ''
          ${python3}/bin/python ${reduce-cache-db} $out/output/cache-db.json ${toString caches} > cache-db.json
          mv cache-db.json $out/output/cache-db.json
        '';
        passthru = {
          inherit globs caches copyOutput;
          inherit package;
          inherit dependencies;
        };
      };
    in
    {
      name = package.pname;
      value = value;
    };
in
builtins.listToAttrs (map build-package inputs)
