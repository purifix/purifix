let purifix = import ../default.nix { };
in
{
  purifix-example = purifix {
    src = ../examples/purescript-package;
  };
}
