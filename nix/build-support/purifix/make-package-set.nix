{ build-package, fetchPackage }:
inputs:
let
  final = builtins.mapAttrs (name: pkg: build-package final (fetchPackage pkg)) inputs;
in
final
