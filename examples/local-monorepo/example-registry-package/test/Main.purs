module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Aff(launchAff_)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (runSpec)

main :: Effect Unit
main = launchAff_ $ runSpec [consoleReporter] do
  describe "true" do
     it "should be true" do
        true `shouldEqual` true
