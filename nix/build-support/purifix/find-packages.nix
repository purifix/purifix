{ lib, fromYAML }:
{ allowMultiWorkspaceBuild, src }:
let

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

        ${before.configPath}

        Redefined in

        ${after.configPath}

        This is disallowed because having a build of packages across multiple
        workspaces is likely to require rebuilding many packages.

        You can either:
        1. call `purifix` with `allowMultiWorkspaceBuild = true` to disable this error
        2. call `purifix` on a source tree that only defines a single workspace
        3. exclude a subtree from the `src` using `lib.cleanSourceWith` or `nix-filter`.
      '';
  parse-package = workspace: dir: trail: configPath: obj:
    let
      this-workspace =
        if obj != null && builtins.hasAttr "workspace" obj then {
          inherit configPath;
          workspace = obj.workspace;
        } else
          null;
      next-workspace = update-workspace workspace this-workspace;
      config = {
        name = obj.package.name;
        value = {
          repo = src;
          src = dir;
          inherit trail;
          inherit configPath;
          config = obj;
          workspace =
            if next-workspace == null then
              builtins.throw "No workspace for package ${obj.package.name}"
            else
              next-workspace.workspace;
        };
      };
    in
    {
      inherit next-workspace;
      config = if obj != null && builtins.hasAttr "package" obj then config else null;
    };
  find-packages = workspace: trail: dir:
    let
      contents = builtins.readDir dir;
      has-yaml = builtins.hasAttr "spago.yaml" contents;
      has-json = builtins.hasAttr "purifix.json" contents;
      names = builtins.attrNames contents;
      directoryNames = builtins.partition (name: contents.${name} == "directory") names;
      directories = map (d: f: f (trail ++ [ d ]) (dir + "/${d}")) directoryNames.right;
      yamlPath = dir + "/spago.yaml";
      yaml = if has-yaml then fromYAML (builtins.readFile yamlPath) else null;
      jsonPath = dir + "/purifix.json";
      json = if has-json then builtins.fromJSON (builtins.readFile jsonPath) else null;
      cfg =
        if has-json then parse-package workspace dir trail jsonPath json
        else if has-yaml then parse-package workspace dir trail yamlPath yaml
        else {
          next-workspace = workspace;
          config = null;
        };
    in
    lib.optionals (cfg.config != null) [ cfg.config ] ++
    builtins.concatLists (map (k: k (find-packages cfg.next-workspace)) directories);
in
find-packages
