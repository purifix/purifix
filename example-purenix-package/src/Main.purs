module Main where

greeting :: String
greeting = "Hello, world!"

data Maybe a = Nothing | Just a

fromMaybe :: forall a. a -> Maybe a -> a
fromMaybe a Nothing = a
fromMaybe _ (Just a) = a

foreign import add :: Int -> Int -> Int

foo :: Int
foo = add 3 5
