{ jq
, fromYAML
, purescript-registry
, purescript-registry-index
, fetchurl
, lib
, stdenv
}:

{ package-set-config
, extra-packages
, src ? null
, subdir ? ""
}:

let

  # Package set version to use from the registry
  registry-version = package-set-config.registry;


  # Parse the package set from the registry at our requested version
  package-set-file =
    if builtins.hasAttr "registry" package-set-config
    then "${purescript-registry}/package-sets/${registry-version}.json"
    else
      fetchurl {
        inherit (package-set-config) url hash;
      };
  registryPackageSet = builtins.fromJSON (builtins.readFile package-set-file);

  readPackageByVersion = package: version:
    let
      meta = builtins.fromJSON (builtins.readFile "${purescript-registry}/metadata/${package}.json");
    in
    meta.published.${version} // {
      type = "registry";
      inherit version;
      location = meta.location;
    };
  readPackageInline = package: meta:
    let
      refLength = builtins.stringLength meta.ref;
      packageConfig = {
        git =
          let
            repo =
              if refLength == 40
              then
              # Assume the "ref" is a commit hash if it's 40 characters long and use
              # it as a revision.
                builtins.fetchGit
                  {
                    url = meta.git;
                    rev = meta.ref;
                    allRefs = true;
                  }
              else
              # Use the ref as is and hope that the source is somewhat stable.
                builtins.fetchGit {
                  url = meta.git;
                  ref = meta.ref;
                };
          in
          {
            type = "inline";
            git = meta.git;
            ref = meta.ref;
            src = repo;
            pname = package;
          } // lib.optionalAttrs (builtins.hasAttr "subdir" meta) {
            subdir = meta.subdir;
          } // lib.optionalAttrs (builtins.hasAttr "dependencies" meta) {
            inherit (meta) dependencies;
          };
        local =
          let
            absolute = builtins.substring 0 1 meta.path == "/";
            # Getting relative path is somewhat tricky because nix doesn't
            # support .. in what they call subpaths (the string appended to
            # the path).
            # We work around this limitation by using IFD and the `realpath` command.
            relative-path = builtins.readFile (stdenv.mkDerivation {
              name = "get-relative-path-${package}";
              phases = [ "installPhase" ];
              installPhase = ''
                realpath --relative-to="${src}" "${src}/${subdir}/${meta.path}" | tr -d '\n' | tee $out
              '';
            });
          in
          {
            type = "inline";
            src =
              if absolute then /. + meta.path
              else src;
          } // lib.optionalAttrs (! absolute) {
            subdir = relative-path;
          } // lib.optionalAttrs (builtins.hasAttr "dependencies" meta) {
            inherit (meta) dependencies;
          };
      };
      package-type =
        if builtins.hasAttr "path" meta then "local"
        else if builtins.hasAttr "git" meta then "git"
        else builtins.throw "Cannot parse extra package ${package} with meta ${toString meta}";
    in
    packageConfig.${package-type};


  readPackage = package: value:
    if builtins.typeOf value == "string"
    then readPackageByVersion package value
    else readPackageInline package value;

  # Fetch metadata about where to download each package in the package set as
  # well as the hash for the tarball to download.
  basePackages = builtins.mapAttrs readPackage registryPackageSet.packages;
  extraPackages = builtins.mapAttrs readPackage extra-packages;

  registryPackages = basePackages // extraPackages;

  # Lookup metadata in the registry-index by finding the line-separated JSON
  # manifest file in the repo matching the package and filtering out the object
  # matching the required version.
  lookupIndex = package: value:
    let
      version = value.version;
      l = builtins.stringLength package;
      path =
        if l == 2 then "2/${package}"
        else if l == 3 then "3/${builtins.substring 0 1 package}/${package}"
        else "${builtins.substring 0 2 package}/${builtins.substring 2 2 package}/${package}";
      meta = builtins.fromJSON (builtins.readFile (stdenv.mkDerivation {
        name = "index-registry-meta-${package}";
        phases = [ "buildPhase" ];
        buildPhase = ''${jq}/bin/jq -s '.[] | select (.version == "${version}")' < "${purescript-registry-index}/${path}" > $out '';
      }));
    in
    value // {
      type = "registry";
      inherit version;
      pname = package;
      dependencies = builtins.attrNames meta.dependencies;
    };

  lookupSource = package: meta:
    let
      targetPursJSON = builtins.fromJSON (builtins.readFile "${meta.src}/${meta.subdir or ""}/purs.json");
      targetSpagoYAML = fromYAML (builtins.readFile "${meta.src}/${meta.subdir or ""}/spago.yaml");
      toList = x: if builtins.typeOf x == "list" then x else builtins.attrNames x;
      dependencies =
        if builtins.pathExists "${meta.src}/${meta.subdir or ""}/purs.json"
        then toList (targetPursJSON.dependencies or { })
        else toList (targetSpagoYAML.package.dependencies or [ ]);
    in
    meta // {
      type = "inline";
      pname = package;
      inherit dependencies;
    };

  lookupDeps = package: value:
    if builtins.hasAttr "dependencies" value
    then value # don't lookup dependencies if they are already declared
    else
      if value.type == "registry"
      then lookupIndex package value
      else lookupSource package value;
  # Fetch list of dependencies for each package in the package set.
  # This lookup is required to be done in the separate registry-index repo
  # because the package set metadata in the main repo doesn't contain
  # dependency information.
  registryDeps = builtins.mapAttrs lookupDeps registryPackages;
in
{
  packages = registryDeps;
  package-set = registryPackageSet;
}
