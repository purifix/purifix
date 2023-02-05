module Main where

import Prelude

import Effect (Effect)
import Effect.Console (log)
import Example.Dependency(example)

main :: Effect Unit
main = do
  log "🍝"
  log (show example)
