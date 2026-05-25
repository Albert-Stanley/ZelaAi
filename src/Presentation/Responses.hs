{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}

-- | Equivalente ao statusresponses.go: respostas HTTP padronizadas.
module Presentation.Responses
  ( MessageResponse(..)
  , okMessage
  ) where

import Data.Aeson (ToJSON)
import GHC.Generics (Generic)

data MessageResponse = MessageResponse
  { message :: String
  } deriving (Generic, Show, ToJSON)

okMessage :: String -> MessageResponse
okMessage = MessageResponse
