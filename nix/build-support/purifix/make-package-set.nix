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
, compiler
, withDocs
, copyFiles
, backends
, filterPackages ? (pkg: true)
, backend
, fetchPackage
}: inputs:
let
  build-package = package:
    let
      get-dep = dep: final.${dep};
      directs = builtins.listToAttrs (map (name: { name = name; value = get-dep name; }) package.dependencies);
      test-deps = package.test.dependencies or [ ];
      transitive = builtins.foldl' (a: pkg: a // final.${pkg}.dependencies) { } (package.dependencies ++ test-deps);
      dependencies = transitive // directs;
      deps = builtins.attrNames dependencies;
      direct-deps = builtins.attrNames directs;
      backendArgs = [ backend.cmd or "" ] ++ (backend.args or [ ]);
      backendCommand = toString backendArgs;
      codegen = if backendCommand == "" then "js" else "corefn";
      # testMain = package.test.main or "Test.Main";
      # testCommand =
      #   if backendCommand == "" then ''
      #     cp -r -L output test-output
      #     node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from './test-output/${testMain}/index.js'; main();" | tee $out
      #   '' else ''
      #     cp -r -L output test-output
      #     ${backend.cmd} --run ${testMain}.main ${toString (backend.args or [])}
      #   '';
      copyOutput = map (dep: ''${get-dep dep}/output/*'') (builtins.filter filterPackages direct-deps);
      caches = map (dep: ''${get-dep dep}/output/cache-db.json'') (builtins.filter filterPackages deps);
      globs = map (dep: ''"${(get-dep dep).package.src}/src/**/*.purs"'') (builtins.filter filterPackages deps);
      isLocal = package.isLocal;
      prepareCommand =
        if copyFiles then
          "echo ${toString copyOutput} | xargs cp --no-clobber -r --preserve -t output"
        else
          "echo ${toString copyOutput} | xargs ${linkFiles} output";
      preparePhase = ''
        mkdir -p output
      '' + lib.optionalString (builtins.length direct-deps > 0) ''
        ${prepareCommand}
        chmod -R +w output
        rm output/cache-db.json
        rm output/package.json
        ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
      '';
      copy-deps = stdenv.mkDerivation {
        pname = "${package.pname}-deps";
        version = package.version or "0.0.0";
        phases = [ "preparePhase" "installPhase" ];
        inherit preparePhase;
        installPhase = ''
          mkdir -p "$out"
          mv output "$out/"
        '';
      };
      value = stdenv.mkDerivation {
        pname = package.pname;
        version = package.version or "0.0.0";
        phases = [ "preparePhase" "buildPhase" "installPhase" "checkPhase" "fixupPhase" ];
        nativeBuildInputs = [
          compiler
        ] ++ backends;
        inherit preparePhase;
        buildPhase = ''
          purs compile --codegen "${codegen}${lib.optionalString withDocs ",docs"}" ${toString globs} "${package.src}/src/**/*.purs"
          ${backendCommand}
        '';
        checkPhase = ''
          if [ -d "${package.src}/test" ]; then
            purs compile --codegen "${codegen}${lib.optionalString withDocs ",docs"}" ${toString globs} "${package.src}/test/**/*.purs"
          fi
        '';
        installPhase = ''
          mkdir -p "$out"
          mv output "$out/"
        '';
        fixupPhase = ''
          ${python3}/bin/python ${reduce-cache-db} $out/output/cache-db.json ${toString caches} > cache-db.json
          mv cache-db.json $out/output/cache-db.json
        '';
        doCheck = false;
        passthru = {
          inherit globs caches copyOutput;
          inherit package;
          inherit dependencies;
          inherit isLocal;
          deps = copy-deps;
        };
      };
    in
    value;
  final = builtins.mapAttrs (name: pkg: build-package (fetchPackage pkg)) inputs;
in
final
