{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- | DTOs do recurso /occurrences.
module Dto.OccurrenceDto
  ( CreateOccurrenceDto(..)
  , OccurrenceResponseDto(..)
  , UpdateStatusDto(..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Data.Int (Int64)
import Data.Time (UTCTime)

data CreateOccurrenceDto = CreateOccurrenceDto
  { categoryId  :: Int64
  , title       :: String
  , description :: String
  , photoUrl    :: String
  , latitude    :: Maybe Double
  , longitude   :: Maybe Double
  , cep         :: Maybe String   -- se vazio, usa o cep do user logado
  } deriving (Generic, Show, FromJSON, ToJSON)

data UpdateStatusDto = UpdateStatusDto
  { newStatus :: String       -- "open" | "in_progress" | "resolved"
  } deriving (Generic, Show, FromJSON, ToJSON)

data OccurrenceResponseDto = OccurrenceResponseDto
  { occId          :: Int64
  , occTitle       :: String
  , occDescription :: String
  , occPhotoUrl    :: String
  , occStatus      :: String
  , occCep         :: String
  , occCity        :: String
  , occUf          :: String
  , occLatitude    :: Maybe Double
  , occLongitude   :: Maybe Double
  , occCreatedAt   :: UTCTime
  , occResolvedAt  :: Maybe UTCTime
  , occUserId      :: Int64
  , occCategoryId  :: Int64
  , occMandateId   :: Maybe Int64
  , occVoteCount   :: Int
  } deriving (Generic, Show, ToJSON)
