{-# LANGUAGE OverloadedStrings #-}

-- | UC13 — Calculo do termometro de gestao para um mandato.
--
-- Score = quanto da carga reportada na gestao ja foi resolvida,
-- + soma de votos (engajamento popular),
-- + tempo medio de resolucao.
module UseCase.ScoreCase
  ( calculateScore
  ) where

import Data.Time (NominalDiffTime, diffUTCTime)
import Database.Persist (Entity(..), get, selectList, count, (==.))
import Database.Persist.Sql (ConnectionPool, runSqlPool, toSqlKey)

import qualified Dto.MandateDto as D
import qualified Repository.Entities as E
import qualified UseCase.MandateCase as MC

-- | Devolve Nothing se o mandato nao existe.
calculateScore
  :: ConnectionPool
  -> Int            -- ^ mandate id
  -> IO (Maybe D.ScoreResponseDto)
calculateScore pool midInt = do
  let mid = toSqlKey (fromIntegral midInt) :: E.MandateId
  mm <- runSqlPool (get mid) pool
  case mm of
    Nothing -> return Nothing
    Just m  -> do
      -- politico
      mp <- runSqlPool (get (E.mandatePoliticianId m)) pool
      let polEntity = case mp of
            Just p  -> Entity (E.mandatePoliticianId m) p
            Nothing -> Entity (E.mandatePoliticianId m) (E.Politician "?" "?" "?")
      let mandateDto = MC.mandateToDto (Entity mid m) polEntity

      -- ocorrencias do mandato
      occs <- runSqlPool (selectList
                [ E.OccurrenceMandateId ==. Just mid
                , E.OccurrenceDeletedAt ==. Nothing
                ] []) pool
      let totalCount = length occs
          resolved   = [ (E.occurrenceCreatedAt o, rs)
                       | Entity _ o <- occs
                       , E.occurrenceStatus o == "resolved"
                       , Just rs <- [E.occurrenceResolvedAt o]
                       ]
          resolvedCount = length resolved
          pct = if totalCount == 0
                  then 0
                  else 100 * fromIntegral resolvedCount / fromIntegral totalCount
          durations :: [NominalDiffTime]
          durations = [ diffUTCTime r c | (c, r) <- resolved ]
          avgSecs :: Double
          avgSecs = if null durations
                      then 0
                      else realToFrac (sum durations) / fromIntegral (length durations)
          avgDays = avgSecs / 86400

      -- soma de votos das ocorrencias
      totalVotes <- sumVotes pool occs

      return $ Just D.ScoreResponseDto
        { D.scoreMandate       = mandateDto
        , D.scoreTotal         = totalCount
        , D.scoreResolved      = resolvedCount
        , D.scoreResolvedPct   = pct
        , D.scoreAvgDaysToFix  = avgDays
        , D.scoreTotalVotes    = totalVotes
        }

sumVotes :: ConnectionPool -> [Entity E.Occurrence] -> IO Int
sumVotes pool = go 0
  where
    go acc []                   = return acc
    go acc (Entity oid _ : rest) = do
      n <- runSqlPool (count [E.VoteOccurrenceId ==. oid]) pool
      go (acc + n) rest
