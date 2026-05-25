{-# LANGUAGE OverloadedStrings #-}

-- | Casos de uso de Occurrence: criar, listar com ranking, buscar por id,
-- listar por CEP. No create, vincula o mandato vigente pra cidade/uf.
module UseCase.OccurrenceCase
  ( createOccurrence
  , listOccurrences
  , getOccurrence
  , listByCep
  , updateStatus
  , listMyOccurrences
  ) where

import Data.Time (getCurrentTime, utctDay)
import Data.Maybe (fromMaybe)
import Data.List (sortOn)
import Data.Ord (Down(..))
import Database.Persist
  ( Entity(..), get, selectList, selectFirst, insert, update, count
  , (==.), (<=.), (>=.), (=.)
  )
import Database.Persist.Sql (ConnectionPool, runSqlPool, fromSqlKey, toSqlKey)

import qualified Dto.OccurrenceDto as D
import qualified Repository.Entities as E
import qualified InterfaceAdapters.Apis as Apis
import qualified InterfaceAdapters.Logs as Logs

-- | Cria uma ocorrencia. Recebe o userId ja extraido do JWT.
-- Resolve cep/city/uf: se o dto traz cep, consulta ViaCEP; senao usa o do user.
createOccurrence
  :: ConnectionPool
  -> E.UserId
  -> D.CreateOccurrenceDto
  -> IO (Either String D.OccurrenceResponseDto)
createOccurrence pool uid dto = do
  -- 1) Categoria existe?
  let cid = toSqlKey (D.categoryId dto) :: E.CategoryId
  mcat <- runSqlPool (get cid) pool
  case mcat of
    Nothing -> return $ Left "category not found"
    Just _  -> do
      -- 2) busca user logado pra default de cep/city/uf
      muser <- runSqlPool (get uid) pool
      case muser of
        Nothing -> return $ Left "user not found"
        Just u  -> do
          -- 3) resolve cep/city/uf (ViaCEP se o dto trouxe cep)
          (cepFinal, cityFinal, ufFinal) <- resolveLocation u (D.cep dto)
          -- 4) busca mandato vigente
          today <- fmap utctDay getCurrentTime
          mMandate <- runSqlPool
            (selectFirst
              [ E.MandateCity ==. cityFinal
              , E.MandateUf   ==. ufFinal
              , E.MandateStartDate <=. today
              , E.MandateEndDate   >=. today
              ] []) pool
          let mandateKey = fmap entityKey mMandate
          -- 5) persist
          now <- getCurrentTime
          let occ = E.Occurrence
                      { E.occurrenceUserId      = uid
                      , E.occurrenceCategoryId  = cid
                      , E.occurrenceMandateId   = mandateKey
                      , E.occurrenceTitle       = D.title dto
                      , E.occurrenceDescription = D.description dto
                      , E.occurrencePhotoUrl    = D.photoUrl dto
                      , E.occurrenceLatitude    = D.latitude dto
                      , E.occurrenceLongitude   = D.longitude dto
                      , E.occurrenceCep         = cepFinal
                      , E.occurrenceCity        = cityFinal
                      , E.occurrenceUf          = ufFinal
                      , E.occurrenceStatus      = "open"
                      , E.occurrenceCreatedAt   = now
                      , E.occurrenceResolvedAt  = Nothing
                      }
          newKey <- runSqlPool (insert occ) pool
          Logs.logInfo $ "occurrence created: " ++ show (fromSqlKey newKey)
          return $ Right (toDto (Entity newKey occ) 0)

-- | Lista todas ocorrencias ordenadas por votos desc.
listOccurrences :: ConnectionPool -> IO [D.OccurrenceResponseDto]
listOccurrences pool = do
  occs <- runSqlPool (selectList [] []) pool
  withVotes <- mapM (attachVoteCount pool) occs
  return $ sortOn (Down . D.occVoteCount) withVotes

-- | Busca uma ocorrencia por id.
getOccurrence :: ConnectionPool -> Int -> IO (Maybe D.OccurrenceResponseDto)
getOccurrence pool oidInt = do
  let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
  mo <- runSqlPool (get oid) pool
  case mo of
    Nothing -> return Nothing
    Just o  -> Just <$> attachVoteCount pool (Entity oid o)

-- | Lista ocorrencias com cep especifico, ordenadas por votos desc.
listByCep :: ConnectionPool -> String -> IO [D.OccurrenceResponseDto]
listByCep pool cepStr = do
  occs <- runSqlPool (selectList [E.OccurrenceCep ==. cepStr] []) pool
  withVotes <- mapM (attachVoteCount pool) occs
  return $ sortOn (Down . D.occVoteCount) withVotes

-- | Atualiza apenas o status. Se virar "resolved", grava resolvedAt = now.
updateStatus
  :: ConnectionPool
  -> Int            -- ^ occurrence id
  -> String         -- ^ novo status
  -> IO (Either String D.OccurrenceResponseDto)
updateStatus pool oidInt newSt = do
  if newSt `notElem` ["open", "in_progress", "resolved"]
    then return $ Left "invalid status"
    else do
      let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
      mo <- runSqlPool (get oid) pool
      case mo of
        Nothing -> return $ Left "occurrence not found"
        Just _  -> do
          now <- getCurrentTime
          let baseUpd = [E.OccurrenceStatus =. newSt]
              fullUpd = if newSt == "resolved"
                          then E.OccurrenceResolvedAt =. Just now : baseUpd
                          else if newSt == "open"
                                 then E.OccurrenceResolvedAt =. Nothing : baseUpd
                                 else baseUpd
          runSqlPool (update oid fullUpd) pool
          Logs.logInfo $ "occurrence " ++ show oidInt ++ " -> status " ++ newSt
          mu <- runSqlPool (get oid) pool
          case mu of
            Nothing -> return $ Left "occurrence vanished after update"
            Just u  -> Right <$> attachVoteCount pool (Entity oid u)

-- | Lista ocorrencias do user logado, ordenadas por createdAt desc (mais recentes primeiro).
listMyOccurrences :: ConnectionPool -> E.UserId -> IO [D.OccurrenceResponseDto]
listMyOccurrences pool uid = do
  occs <- runSqlPool (selectList [E.OccurrenceUserId ==. uid] []) pool
  withVotes <- mapM (attachVoteCount pool) occs
  -- ordena por createdAt desc
  return $ sortOn (Down . D.occCreatedAt) withVotes

-- Helpers ------------------------------------------------------------

attachVoteCount :: ConnectionPool -> Entity E.Occurrence -> IO D.OccurrenceResponseDto
attachVoteCount pool ent@(Entity oid _) = do
  n <- runSqlPool (count [E.VoteOccurrenceId ==. oid]) pool
  return (toDto ent n)

toDto :: Entity E.Occurrence -> Int -> D.OccurrenceResponseDto
toDto (Entity oid o) votes = D.OccurrenceResponseDto
  { D.occId          = fromSqlKey oid
  , D.occTitle       = E.occurrenceTitle o
  , D.occDescription = E.occurrenceDescription o
  , D.occPhotoUrl    = E.occurrencePhotoUrl o
  , D.occStatus      = E.occurrenceStatus o
  , D.occCep         = E.occurrenceCep o
  , D.occCity        = E.occurrenceCity o
  , D.occUf          = E.occurrenceUf o
  , D.occLatitude    = E.occurrenceLatitude o
  , D.occLongitude   = E.occurrenceLongitude o
  , D.occCreatedAt   = E.occurrenceCreatedAt o
  , D.occResolvedAt  = E.occurrenceResolvedAt o
  , D.occUserId      = fromSqlKey (E.occurrenceUserId o)
  , D.occCategoryId  = fromSqlKey (E.occurrenceCategoryId o)
  , D.occMandateId   = fmap fromSqlKey (E.occurrenceMandateId o)
  , D.occVoteCount   = votes
  }

-- | Se o DTO trouxer cep, consulta ViaCEP; senao usa o cep/city/uf do user.
resolveLocation
  :: E.User
  -> Maybe String
  -> IO (String, String, String)
resolveLocation u Nothing =
  return (E.userCep u, E.userCity u, E.userUf u)
resolveLocation u (Just cepStr) = do
  res <- Apis.fetchCep cepStr
  case res of
    Left _   -> return (E.userCep u, E.userCity u, E.userUf u)   -- fallback
    Right vc -> return
      ( cepStr
      , fromMaybe (E.userCity u) (Apis.localidade vc)
      , fromMaybe (E.userUf u)   (Apis.uf vc)
      )
