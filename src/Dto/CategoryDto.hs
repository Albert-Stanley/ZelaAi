{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- | DTOs do recurso /categories.
module Dto.CategoryDto
  ( CategoryResponseDto(..)
  ) where

import Data.Aeson (ToJSON)
import GHC.Generics (Generic)
import Data.Int (Int64)

data CategoryResponseDto = CategoryResponseDto
  { categoryId   :: Int64
  , categoryName :: String
  } deriving (Generic, Show, ToJSON)
