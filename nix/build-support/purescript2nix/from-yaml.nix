{ yaml2json, stdenv }:
# Parse text containing YAML content into a nix expression.
yaml:
builtins.fromJSON (builtins.readFile (stdenv.mkDerivation {
  preferLocalBuild = true;
  allowSubstitutes = false;
  name = "fromYAML";
  phases = [ "buildPhase" ];
  buildPhase = "echo '${yaml}' | ${yaml2json}/bin/yaml2json > $out";
}))
