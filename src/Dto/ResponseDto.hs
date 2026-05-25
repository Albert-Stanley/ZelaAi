{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- | Equivalente a ResponseControllerDTO / ResponseErrorDTO do TCC.
module Dto.ResponseDto
  ( ResponseControllerDto(..)
  , ResponseErrorDto(..)
  ) where

import Data.Aeson (ToJSON)
import GHC.Generics (Generic)

data ResponseControllerDto = ResponseControllerDto
  { message :: String
  } deriving (Generic, Show, ToJSON)

data ResponseErrorDto = ResponseErrorDto
  { errorMessage :: String
  } deriving (Generic, Show, ToJSON)
