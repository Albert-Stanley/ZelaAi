{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- | DTOs do recurso /politicians, /mandates e /mandates/:id/score.
module Dto.MandateDto
  ( CreatePoliticianDto(..)
  , PoliticianResponseDto(..)
  , CreateMandateDto(..)
  , MandateResponseDto(..)
  , ScoreResponseDto(..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Data.Int (Int64)
import Data.Time (Day)

-- ------- Politician

data CreatePoliticianDto = CreatePoliticianDto
  { polName  :: String
  , polParty :: String
  , polRole  :: String        -- "prefeito" | "governador"
  } deriving (Generic, Show, FromJSON, ToJSON)

data PoliticianResponseDto = PoliticianResponseDto
  { politicianId    :: Int64
  , politicianName  :: String
  , politicianParty :: String
  , politicianRole  :: String
  } deriving (Generic, Show, ToJSON)

-- ------- Mandate

data CreateMandateDto = CreateMandateDto
  { manPoliticianId :: Int64
  , manCity         :: String
  , manUf           :: String
  , manStartDate    :: Day     -- formato JSON: "2024-01-01"
  , manEndDate      :: Day     -- formato JSON: "2027-12-31"
  } deriving (Generic, Show, FromJSON, ToJSON)

data MandateResponseDto = MandateResponseDto
  { mandateId        :: Int64
  , mandatePolitician :: PoliticianResponseDto
  , mandateCity      :: String
  , mandateUf        :: String
  , mandateStartDate :: Day
  , mandateEndDate   :: Day
  } deriving (Generic, Show, ToJSON)

-- ------- Score

data ScoreResponseDto = ScoreResponseDto
  { scoreMandate        :: MandateResponseDto
  , scoreTotal          :: Int      -- total de ocorrencias vinculadas
  , scoreResolved       :: Int      -- quantas resolvidas
  , scoreResolvedPct    :: Double   -- 0..100
  , scoreAvgDaysToFix   :: Double   -- media de dias ate resolver
  , scoreTotalVotes     :: Int      -- soma de votos das ocorrencias
  } deriving (Generic, Show, ToJSON)
