{ writeShellScript }:
writeShellScript "link-files" ''
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
     elif [ ! -e "output/$name" ]; then
        links+=( "$file" )
     fi
  done
  if [[ ''${#copies[*]} > 0 ]]; then
    cp -r --no-clobber -t output "''${copies[@]}"
  fi
  if [[ ''${#links[*]} > 0 ]]; then
    ln -s -t output "''${links[@]}"
  fi
''
