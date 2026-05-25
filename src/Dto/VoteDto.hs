{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- | DTOs do recurso /votes.
module Dto.VoteDto
  ( VoteResponseDto(..)
  ) where

import Data.Aeson (ToJSON)
import GHC.Generics (Generic)
import Data.Int (Int64)

-- | Resposta padrao depois de votar/desvotar: devolve a contagem nova
-- pra o frontend atualizar sem precisar refetch.
data VoteResponseDto = VoteResponseDto
  { occurrenceId :: Int64
  , voteCount    :: Int
  , message      :: String
  } deriving (Generic, Show, ToJSON)
