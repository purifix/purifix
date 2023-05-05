{ jq
, stdenv
, lib
, python3
, writeText
, linkFiles
, nix
, tree
}:
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
{ compiler
, withDocs
, copyFiles
, backends
, backend
}:
final: package:
let
  get-dep = dep: final.${dep};
  directs = builtins.listToAttrs (map (name: { name = name; value = get-dep name; }) package.dependencies);
  test-directs = builtins.listToAttrs (map (name: { name = name; value = get-dep name; }) (package.test.dependencies or [ ]));
  test-dependencies = builtins.attrNames test-directs;
  direct-deps = builtins.attrNames directs;
  transitive = builtins.foldl' (a: pkg: a // final.${pkg}.dependencies) { } direct-deps;
  test-transitive = builtins.foldl' (a: pkg: a // final.${pkg}.dependencies) { } test-dependencies;
  dependencies = transitive // directs;
  deps = builtins.attrNames dependencies;
  test-deps = builtins.attrNames (test-transitive // transitive // test-directs // directs);
  backendArgs = [ backend.cmd or "" ] ++ (backend.args or [ ]);
  backendCommand = toString backendArgs;
  codegen = if backendCommand == "" then "js" else "corefn";
  testMain = package.test.main or "Test.Main";
  testCommand =
    if backendCommand == "" then ''
      cp -r -L output test-output
      node --input-type=module --abort-on-uncaught-exception --trace-sigint --trace-uncaught --eval="import {main} from './test-output/${testMain}/index.js'; main();" | tee $out
    '' else ''
      cp -r -L output test-output
      ${backend.cmd} --run ${testMain}.main ${toString (backend.args or [])}
    '';
  unique = xs: builtins.attrNames (builtins.listToAttrs (map
    (x: {
      name = x;
      value = null;
    })
    xs));
  copyOutput = map (dep: ''${get-dep dep}/output/*'') direct-deps;
  copyTestOutput = map (dep: ''${get-dep dep}/output/*'') (unique (direct-deps ++ test-dependencies));
  caches = map (dep: ''${get-dep dep}/output/cache-db.json'') deps;
  test-caches = map (dep: ''${get-dep dep}/output/cache-db.json'') test-deps;
  globs = map (dep: ''"${(get-dep dep).package.src}/src/**/*.purs"'') deps;
  test-globs = map (dep: ''"${(get-dep dep).package.src}/src/**/*.purs"'') (unique (deps ++ test-deps));
  isLocal = package.isLocal;
  prepareCommand = outputs:
    if copyFiles then
      "echo ${toString outputs} | xargs cp --no-clobber -r --preserve -t output"
    else
      "echo ${toString outputs} | xargs ${linkFiles} output";
  preparePhase = ''
    mkdir -p output
  '' + lib.optionalString (builtins.length direct-deps > 0) ''
    ${prepareCommand copyOutput}
    chmod -R +w output
    rm output/cache-db.json
    rm output/package.json
    ${jq}/bin/jq -s add ${toString caches} > output/cache-db.json
  '';
  prepareTests = ''
    mkdir -p output
  '' + lib.optionalString (builtins.length (test-deps) > 0) ''
    ${prepareCommand copyTestOutput}
    chmod -R +w output
    rm output/cache-db.json
    rm output/package.json
    ${jq}/bin/jq -s add ${toString test-caches} > output/cache-db.json
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
        ${prepareTests}
        purs compile --codegen "${codegen}" ${toString test-globs} "${package.src}/src/**/*.purs" "${package.src}/test/**/*.purs"
        ${testCommand}
        # FIXME: move this into purenix
        if [[ "${backend.cmd}" == "purenix" ]]; then
          mkdir tmp-nix
          export NIX_STORE_PATH=$(pwd)/tmp-nix/store
          export NIX_DATA_DIR=$(pwd)/tmp-nix/share
          export NIX_LOG_DIR=$(pwd)/tmp-nix/log/nix
          export NIX_STATE_DIR=$(pwd)/tmp-nix/log/nix
          ${nix}/bin/nix-instantiate --eval --readonly-mode -E "let module = import ./output/Test.Main; in module.main null"
        fi
      fi
    '';
    installPhase = ''
      mkdir -p "$out"
      mv output "$out/"
    '';
    fixupPhase = ''
      ${python3}/bin/python ${reduce-cache-db} $out/output/cache-db.json ${toString caches} > cache-db.json
      cp -f cache-db.json $out/output/cache-db.json
    '';
    doCheck = true;
    passthru = {
      inherit globs caches copyOutput;
      inherit package;
      inherit dependencies;
      inherit isLocal;
      deps = copy-deps;
    };
  };
in
value
