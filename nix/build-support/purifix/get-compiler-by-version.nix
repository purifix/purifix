{ easy-ps, lib, purescript }: version:

let
  major = lib.versions.major version;
  minor = lib.versions.minor version;
  patch = lib.versions.patch version;
  compiler-name = "purs-${major}_${minor}_${patch}";
  fallback = builtins.trace ''
    Couldn't select purescript compiler with version ${version}.
    Using version ${purescript.version} from nixpkgs instead.
  ''
    purescript;
in
  easy-ps.${compiler-name} or fallback
