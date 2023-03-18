{ writeShellScript }:
writeShellScript "link-files" ''
  outdir="$1"
  shift
  copies=()
  links=()
  declare -A visited
  for file in "$@"; do
     name=$(basename "$file")
     if [[ ''${visited[$name]} == 1 ]]; then
       continue
     fi
     visited[$name]=1
     if [[ "$name" == Prim* ]]; then
        copies+=( "$file" )
     elif [ ! -e "$outdir/$name" ]; then
        links+=( "$file" )
     fi
  done
  if [[ ''${#copies[*]} > 0 ]]; then
    cp -r --no-clobber -t "$outdir" "''${copies[@]}"
  fi
  if [[ ''${#links[*]} > 0 ]]; then
    ln -s -t "$outdir" "''${links[@]}"
  fi
''
