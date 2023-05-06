{ build-package, fetchPackage }:
inputs: final:
builtins.mapAttrs (name: pkg: build-package final (fetchPackage pkg)) inputs
