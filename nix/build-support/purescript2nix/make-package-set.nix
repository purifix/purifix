{ jq, stdenv, lib }:
{ storage-backend
, packages
, codegen
, compiler
, fetch-sources
, backendCommand
, withDocs ? true
}: final: inputs:
let
  build-package = package:
    let
      copyOutput = map (dep: let pkg = final.${dep}; in ''${pkg}/output/*'') package.dependencies;
      dependency-closure = fetch-sources {
        inherit packages storage-backend;
        dependencies = package.dependencies;
      };
      caches = map (dep: let pkg = final.${dep}; in ''${pkg}/output/cache-db.json'') package.dependencies;
      nixCaches = map (dep: let pkg = final.${dep}; in builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile ''${pkg}/output/cache-db.json''))) package.dependencies;
      noDup = a: b:
        let
          common = builtins.attrNames (builtins.intersectAttrs a b);
          consistent = acc: key: if a.${key} == b.${key} then acc else builtins.throw "Duplicate module ${key}";
        in
        if builtins.length common > 0
        then a // b // builtins.foldl' consistent { } common
        else a // b;
      mergeModules = builtins.foldl' noDup { } nixCaches;

      globs = map (dep: ''"${dep.src}/${dep.subdir or ""}/src/**/*.purs"'') dependency-closure.packages;
      value = builtins.seq mergeModules (stdenv.mkDerivation {
        pname = package.pname;
        version = package.version or "0.0.0";
        phases = [ "preparePhase" "buildPhase" "installPhase" ];
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
          purs compile --codegen "${codegen}${lib.optionalString withDocs ",docs"}" ${toString globs} "${package.src}/${package.subdir or ""}/src/**/*.purs"
          ${backendCommand}
        '';
        installPhase = ''
          mkdir -p "$out"
          cp -r output "$out/"
        '';
        passthru = {
          inherit globs caches copyOutput;
          inherit package;
        };
      });
    in
    {
      name = package.pname;
      value = value;
    };
in
builtins.listToAttrs (map build-package inputs)
