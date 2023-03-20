{ fromYAML
, purescript-registry
, purescript-registry-index
, fetchurl
, lib
, stdenv
}:

{ package-set-config
, extra-packages
, repo ? null
, src ? null
}:

let

  # Package set version to use from the registry
  registry-version = package-set-config.registry;


  # Parse the package set from the registry at our requested version
  registryPackageSet =
    if builtins.hasAttr "registry" package-set-config
    then builtins.fromJSON (builtins.readFile "${purescript-registry}/package-sets/${registry-version}.json")
    else
      if builtins.hasAttr "inline" package-set-config
      then package-set-config.inline
      else
        builtins.fromJSON (builtins.readFile (fetchurl {
          inherit (package-set-config) url hash;
        }));

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
            src =
              if builtins.hasAttr "subdir" meta
              then builtins.path { path = repo + "/${meta.subdir}"; }
              else builtins.path { path = repo; };
            repo = repo;
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
              preferLocalBuild = true;
              allowSubstitutes = false;
              name = "get-relative-path-${package}";
              phases = [ "installPhase" ];
              installPhase = ''
                realpath --relative-to="${repo}" "${src}/${meta.path}" | tr -d '\n' | tee $out
              '';
            });
            package-src =
              if absolute
              then
                builtins.path
                  {
                    path = /. + meta.path;
                  }
              else
                builtins.path {
                  path = src + "/${relative-path}";
                }
            ;
            package-repo = if absolute then package-src else repo;
          in
          {
            type = "inline";
            repo = package-repo;
            src = package-src;
          } // lib.optionalAttrs (! absolute) {
            subdir = relative-path;
          } // lib.optionalAttrs (builtins.hasAttr "dependencies" meta) {
            inherit (meta) dependencies;
          }
        ;
        parsed = meta.config.package // {
          type = "inline";
          repo = meta.repo;
          src = meta.src;
          pname = meta.config.package.name;
          dependencies = meta.config.package.dependencies or [ ];
        };
      };
      package-type =
        if builtins.hasAttr "config" meta then "parsed"
        else if builtins.hasAttr "path" meta then "local"
        else if builtins.hasAttr "git" meta then "git"
        else builtins.throw "Cannot parse extra package ${package} with meta ${toString (builtins.toJSON meta)}";
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

  read-meta = version: file:
    let
      text = builtins.readFile file;
      lines = builtins.filter (line: line != "") (lib.splitString "\n" text);
      values = lib.reverseList (map builtins.fromJSON lines);
      byVersion = builtins.listToAttrs (map (x: { name = x.version; value = x; }) values);
    in
    byVersion.${version};

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
      meta = read-meta version "${purescript-registry-index}/${path}";
    in
    value // {
      type = "registry";
      inherit version;
      pname = package;
      dependencies = builtins.attrNames meta.dependencies;
    };

  lookupSource = package: meta:
    let
      targetPursJSON = builtins.fromJSON (builtins.readFile "${meta.src}/purs.json");
      targetPurifixJSON = builtins.fromJSON (builtins.readFile "${meta.src}/purifix.json");
      targetSpagoYAML = fromYAML (builtins.readFile "${meta.src}/spago.yaml");
      toList = x: if builtins.typeOf x == "list" then x else builtins.attrNames x;
      dependencies =
        if builtins.pathExists "${meta.src}/purifix.json"
        then
          toList (targetPurifixJSON.dependencies or [ ])
        else if builtins.pathExists "${meta.src}/purs.json"
        then
          toList (targetPursJSON.dependencies or { })
        else
          toList (targetSpagoYAML.package.dependencies or [ ]);
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
