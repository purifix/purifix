{ easy-ps, lib }: version:

let
  major = lib.versions.major version;
  minor = lib.versions.minor version;
  patch = lib.versions.patch version;
  compiler-name = "purs-${major}_${minor}_${patch}";
in
easy-ps.${compiler-name}
