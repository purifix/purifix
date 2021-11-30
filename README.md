# purescript2nix

This is a tool for easily building PureScript projects with Nix.

The advantage of `purescript2nix` is that your `spago.dhall` and
`packages.dhall` files act as a single source of truth.  When
you update dependencies in `spago.dhall` or the package set in
`packages.dhall`, you don't need to update the Nix expression
at all.  It automatically picks up changes from these two
Dhall files.

Using `purescript2nix` on a PureScript packages looks like the
following. This is how you would build the PureScript package
[`./example-purescript-package/`](./example-purescript-package/)
with `purescript2nix`:


```nix
purescript2nix {
  pname = "example-purescript-package";
  src = ./example-purescript-package;
};
```

## Installing / Getting `purescript2nix`

The `purescript2nix` function lives in this repo, so I would recommend either
adding `purescript2nix` as a flake input and using the provided overlay, or
just directly importing the `purescript2nix` repo and applying
[`./nix/overlay.nix`](./nix/overlay.nix).

## Using the `purescript2nix` function

Using the `purescript2nix` function to build your package is as simple as
calling it with `pname` and `src` arguments.  See either the above example, or
the `example-purescript-package` attribute in
[`./nix/overlay.nix`](./nix/overlay.nix) and the
[example PureScript package](./example-purescript-package/).

## Building the derivation produced by `purescript2nix`

Building the derivation produced by `purescript2nix` is as simple as calling
`nix-build` on it.  Here is how you would build the example PureScript package
in this repo:

```console
$ nix-build ./nix -A example-purescript-package
...
/nix/store/z3gvwhpnp0rfi65dgxmk1rjycpa4l1ag-example-purescript-package
```

This produces an output with a single directory `output/`.  `output/` contains
all the transpiled PureScript code:

```console
$ tree /nix/store/z3gvwhpnp0rfi65dgxmk1rjycpa4l1ag-example-purescript-package
/nix/store/z3gvwhpnp0rfi65dgxmk1rjycpa4l1ag-example-purescript-package
└── output
    ├── cache-db.json
    ├── Control.Alt
    │   ├── externs.cbor
    │   └── index.js
    ├── Control.Alternative
    │   ├── externs.cbor
    │   └── index.js
    ├── Control.Applicative
    │   ├── externs.cbor
    │   └── index.js
    ├── Control.Apply
    │   ├── externs.cbor
    │   ├── foreign.js
...
```

## Caveats

One big problem with `purescript2nix` is that it requires a package set with
hashes.  The `purescript/package-sets` repo does not include hashes for
packages in the package set.  See
[#4](https://github.com/cdepillabout/purescript2nix/issues/4) for more info.

Also, you might have problem using `purescript2nix` from flakes.  See
[#1](https://github.com/cdepillabout/purescript2nix/issues/1) for more info.
