{-# LANGUAGE OverloadedStrings #-}

-- | Casos de uso de Vote: votar e desvotar.
module UseCase.VoteCase
  ( voteOccurrence
  , unvoteOccurrence
  ) where

import Data.Time (getCurrentTime)
import Database.Persist
  ( get, getBy, insert_, deleteBy, count
  , (==.)
  )
import Database.Persist.Sql (ConnectionPool, runSqlPool, fromSqlKey, toSqlKey)

import qualified Dto.VoteDto as D
import qualified Repository.Entities as E
import qualified InterfaceAdapters.Logs as Logs

-- | Insere voto se ainda nao existir. Retorna Left "already voted" se
-- ja existe (sera traduzido em 409 no controller).
voteOccurrence
  :: ConnectionPool
  -> E.UserId
  -> Int             -- ^ occurrence id (Int64 vindo do path)
  -> IO (Either String D.VoteResponseDto)
voteOccurrence pool uid oidInt = do
  let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
  mo <- runSqlPool (get oid) pool
  case mo of
    Nothing -> return $ Left "occurrence not found"
    Just _  -> do
      existing <- runSqlPool (getBy (E.UniqueUserOccurrence uid oid)) pool
      case existing of
        Just _  -> return $ Left "already voted"
        Nothing -> do
          now <- getCurrentTime
          let v = E.Vote
                    { E.voteUserId       = uid
                    , E.voteOccurrenceId = oid
                    , E.voteCreatedAt    = now
                    }
          runSqlPool (insert_ v) pool
          n <- runSqlPool (count [E.VoteOccurrenceId ==. oid]) pool
          Logs.logInfo $ "vote: user " ++ show (fromSqlKey uid)
                       ++ " -> occ " ++ show (fromSqlKey oid)
          return $ Right D.VoteResponseDto
            { D.occurrenceId = fromSqlKey oid
            , D.voteCount    = n
            , D.message      = "voted"
            }

-- | Remove voto. Retorna Left "vote not found" se nao havia.
unvoteOccurrence
  :: ConnectionPool
  -> E.UserId
  -> Int
  -> IO (Either String D.VoteResponseDto)
unvoteOccurrence pool uid oidInt = do
  let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
  mo <- runSqlPool (get oid) pool
  case mo of
    Nothing -> return $ Left "occurrence not found"
    Just _  -> do
      existing <- runSqlPool (getBy (E.UniqueUserOccurrence uid oid)) pool
      case existing of
        Nothing -> return $ Left "vote not found"
        Just _  -> do
          runSqlPool (deleteBy (E.UniqueUserOccurrence uid oid)) pool
          n <- runSqlPool (count [E.VoteOccurrenceId ==. oid]) pool
          Logs.logInfo $ "unvote: user " ++ show (fromSqlKey uid)
                       ++ " -> occ " ++ show (fromSqlKey oid)
          return $ Right D.VoteResponseDto
            { D.occurrenceId = fromSqlKey oid
            , D.voteCount    = n
            , D.message      = "unvoted"
            }
