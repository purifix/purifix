let upstream =
      -- This is a special PureScript package set that has Nix-compatible
      -- hashes for each package.
      --
      -- Note that you won't need to use a special package set if the
      -- purescript package-set repo starts generating package-sets that include
      -- Nix-compatible hashes.
      https://raw.githubusercontent.com/cdepillabout/package-sets/add-hashes/packages-with-hashes.dhall sha256:1b57a695086213bbff7b9a692bc1049343ae962cbacb5bc5dd9f19c0bf75bf80

in  upstream
