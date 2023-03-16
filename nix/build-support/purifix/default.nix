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
, workspaceYaml ? "${src}/spago.yaml"
, backend ? null
, backendCommand ? lib.optionalString (backend != null) "${backend}/bin/${backend.pname}"
, storage-backend ? package: "https://packages.registry.purescript.org/${package.pname}/${package.version}.tar.gz"
, develop-packages ? null
, allowMultiWorkspaceBuild ? false
, withDocs ? true
, nodeModules ? null
}:

let

  # Parse the workspace global spago.yaml
  workspace = (fromYAML (builtins.readFile workspaceYaml)).workspace;
  # TODO: Support the purs.json file instead/as well? It doesn't seem to
  # support extra_packages but could be ok if there's a global workspace spago.yaml.

  # TODO: Follow symlinks? If so, how to deal with impure paths and path resolution?
  # Find and parse the spago.yaml package files into nix
  update-workspace = before: after:
    if before == null then
      after
    else if after == null then
      before
    else if allowMultiWorkspaceBuild then
      after
    else
      builtins.throw ''
        Error: Redefinition of workspace.

        Workspace originally defined in

        ${before.yamlPath}

        Redefined in

        ${after.yamlPath}

        This is disallowed because having a build of packages across multiple
        workspaces is likely to require rebuilding many packages.

        You can either:
        1. call `purifix` with `allowMultiWorkspaceBuild = true` to disable this error
        2. call `purifix` on a source tree that only defines a single workspace
        3. exclude a subtree from the `src` using `lib.cleanSourceWith` or `nix-filter`.
      '';
  find-packages = workspace: dir:
    let
      contents = builtins.readDir dir;
      names = builtins.attrNames contents;
      directoryNames =
        builtins.partition (name: contents.${name} == "directory") names;
      directories = map (d: dir + "/${d}") directoryNames.right;
      yamlPath = dir + "/spago.yaml";
      yaml = fromYAML (builtins.readFile yamlPath);
      this-workspace =
        if builtins.hasAttr "workspace" yaml then {
          yamlPath = yamlPath;
          workspace = yaml.workspace;
        } else
          null;
      next-workspace =
        if has-config then
          update-workspace workspace this-workspace
        else
          workspace;
      config = {
        name = yaml.package.name;
        value = {
          repo = src;
          src = dir;
          yamlPath = yamlPath;
          yaml = yaml;
          workspace =
            if next-workspace == null then
              builtins.throw "No workspace for package ${yaml.package.name}"
            else
              next-workspace.workspace;
        };
      };
      has-config = builtins.hasAttr "spago.yaml" contents;
      packages = lib.optionals (has-config && builtins.hasAttr "package" yaml)
        [ config ];
    in
    packages
    ++ builtins.concatLists (map (find-packages next-workspace) directories);

  localPackages = builtins.listToAttrs (find-packages null src);

  build-package = callPackage ./build-purifix-package.nix {
    inherit fromYAML purescript-registry purescript-registry-index purescript-language-server;
  };
  package-names = builtins.attrNames localPackages;
  build = name: package-config:
    build-package {
      inherit localPackages package-config;
      inherit backend backendCommand storage-backend develop-packages withDocs nodeModules;
    };
in
if builtins.length package-names == 1 then
  let
    name = builtins.elemAt package-names 0;
    pkg = localPackages.${name};
  in
  build name pkg
else
  let
    purescript-pkgs = builtins.mapAttrs
      (name: pkg: build name pkg // { pkgs = purescript-pkgs; })
      localPackages;
  in
  purescript-pkgs
