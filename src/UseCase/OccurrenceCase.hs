{-# LANGUAGE OverloadedStrings #-}

-- | Casos de uso de Occurrence: criar, listar com ranking, buscar por id,
-- listar por CEP, atualizar status, editar e soft-delete (dono ou admin),
-- e geo-search "nearby" via haversine.
module UseCase.OccurrenceCase
  ( createOccurrence
  , listOccurrences
  , getOccurrence
  , listByCep
  , updateStatus
  , listMyOccurrences
  , updateOccurrence
  , softDeleteOccurrence
  , hardDeleteOccurrence
  , nearbyOccurrences
  ) where

import Data.Time (getCurrentTime, utctDay)
import Data.Maybe (fromMaybe)
import Data.List (sortOn)
import Data.Ord (Down(..))
import Database.Persist
  ( Entity(..), Filter, get, selectList, selectFirst, insert, update, delete, deleteWhere, count
  , (==.), (<=.), (>=.), (=.)
  )
import Database.Persist.Sql (ConnectionPool, runSqlPool, fromSqlKey, toSqlKey)

import qualified Dto.OccurrenceDto as D
import qualified Repository.Entities as E
import qualified InterfaceAdapters.Apis as Apis
import qualified InterfaceAdapters.Logs as Logs

-- | Filtro padrão: exclui ocorrências soft-deleted.
notDeleted :: [Filter E.Occurrence]
notDeleted = [E.OccurrenceDeletedAt ==. Nothing]

-- | Cria uma ocorrencia. Recebe o userId ja extraido do JWT.
-- Resolve cep/city/uf: se o dto traz cep, consulta ViaCEP; senao usa o do user.
createOccurrence
  :: ConnectionPool
  -> E.UserId
  -> D.CreateOccurrenceDto
  -> IO (Either String D.OccurrenceResponseDto)
createOccurrence pool uid dto = do
  let cid = toSqlKey (D.categoryId dto) :: E.CategoryId
  mcat <- runSqlPool (get cid) pool
  case mcat of
    Nothing -> return $ Left "category not found"
    Just _  -> do
      muser <- runSqlPool (get uid) pool
      case muser of
        Nothing -> return $ Left "user not found"
        Just u  -> do
          (cepFinal, cityFinal, ufFinal) <- resolveLocation u (D.cep dto)
          today <- fmap utctDay getCurrentTime
          mMandate <- runSqlPool
            (selectFirst
              [ E.MandateCity ==. cityFinal
              , E.MandateUf   ==. ufFinal
              , E.MandateStartDate <=. today
              , E.MandateEndDate   >=. today
              ] []) pool
          let mandateKey = fmap entityKey mMandate
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
                      , E.occurrenceDeletedAt   = Nothing
                      }
          newKey <- runSqlPool (insert occ) pool
          Logs.logInfo $ "occurrence created: " ++ show (fromSqlKey newKey)
          return $ Right (toDto (Entity newKey occ) 0)

-- | Lista todas ocorrencias não-deletadas, ordenadas por votos desc.
listOccurrences :: ConnectionPool -> IO [D.OccurrenceResponseDto]
listOccurrences pool = do
  occs <- runSqlPool (selectList notDeleted []) pool
  withVotes <- mapM (attachVoteCount pool) occs
  return $ sortOn (Down . D.occVoteCount) withVotes

-- | Busca uma ocorrencia por id. Retorna Nothing se deletada.
getOccurrence :: ConnectionPool -> Int -> IO (Maybe D.OccurrenceResponseDto)
getOccurrence pool oidInt = do
  let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
  mo <- runSqlPool (get oid) pool
  case mo of
    Nothing -> return Nothing
    Just o
      | E.occurrenceDeletedAt o /= Nothing -> return Nothing
      | otherwise -> Just <$> attachVoteCount pool (Entity oid o)

listByCep :: ConnectionPool -> String -> IO [D.OccurrenceResponseDto]
listByCep pool cepStr = do
  occs <- runSqlPool (selectList ((E.OccurrenceCep ==. cepStr) : notDeleted) []) pool
  withVotes <- mapM (attachVoteCount pool) occs
  return $ sortOn (Down . D.occVoteCount) withVotes

updateStatus
  :: ConnectionPool
  -> Int
  -> String
  -> IO (Either String D.OccurrenceResponseDto)
updateStatus pool oidInt newSt = do
  if newSt `notElem` ["open", "in_progress", "resolved"]
    then return $ Left "invalid status"
    else do
      let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
      mo <- runSqlPool (get oid) pool
      case mo of
        Nothing -> return $ Left "occurrence not found"
        Just o
          | E.occurrenceDeletedAt o /= Nothing -> return $ Left "occurrence not found"
          | otherwise -> do
              now <- getCurrentTime
              let baseUpd = [E.OccurrenceStatus =. newSt]
                  fullUpd = if newSt == "resolved"
                              then (E.OccurrenceResolvedAt =. Just now) : baseUpd
                              else if newSt == "open"
                                     then (E.OccurrenceResolvedAt =. Nothing) : baseUpd
                                     else baseUpd
              runSqlPool (update oid fullUpd) pool
              Logs.logInfo $ "occurrence " ++ show oidInt ++ " -> status " ++ newSt
              mu <- runSqlPool (get oid) pool
              case mu of
                Nothing -> return $ Left "occurrence vanished after update"
                Just u  -> Right <$> attachVoteCount pool (Entity oid u)

listMyOccurrences :: ConnectionPool -> E.UserId -> IO [D.OccurrenceResponseDto]
listMyOccurrences pool uid = do
  occs <- runSqlPool (selectList ((E.OccurrenceUserId ==. uid) : notDeleted) []) pool
  withVotes <- mapM (attachVoteCount pool) occs
  return $ sortOn (Down . D.occCreatedAt) withVotes

-- | Atualiza campos editáveis (title/desc/photo/category). Autorização:
-- apenas o dono ou um admin (callsite valida).
updateOccurrence
  :: ConnectionPool
  -> E.UserId         -- ^ user que está fazendo a request (do JWT)
  -> Bool             -- ^ é admin?
  -> Int              -- ^ occurrence id
  -> D.UpdateOccurrenceDto
  -> IO (Either String D.OccurrenceResponseDto)
updateOccurrence pool reqUid isAdmin oidInt dto = do
  let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
  mo <- runSqlPool (get oid) pool
  case mo of
    Nothing -> return $ Left "occurrence not found"
    Just o
      | E.occurrenceDeletedAt o /= Nothing -> return $ Left "occurrence not found"
      | not isAdmin && E.occurrenceUserId o /= reqUid -> return $ Left "forbidden"
      | otherwise -> do
          let upd = concat
                [ maybe [] (\v -> [E.OccurrenceTitle       =. v]) (D.upTitle dto)
                , maybe [] (\v -> [E.OccurrenceDescription =. v]) (D.upDescription dto)
                , maybe [] (\v -> [E.OccurrencePhotoUrl    =. v]) (D.upPhotoUrl dto)
                , maybe [] (\v -> [E.OccurrenceCategoryId  =. toSqlKey v]) (D.upCategoryId dto)
                ]
          if null upd
            then return $ Left "nothing to update"
            else do
              runSqlPool (update oid upd) pool
              Logs.logInfo $ "occurrence " ++ show oidInt ++ " edited by user " ++ show (fromSqlKey reqUid)
              mu <- runSqlPool (get oid) pool
              case mu of
                Nothing -> return $ Left "occurrence vanished"
                Just u  -> Right <$> attachVoteCount pool (Entity oid u)

-- | Soft delete: marca deletedAt = now. Apenas dono ou admin.
softDeleteOccurrence
  :: ConnectionPool
  -> E.UserId
  -> Bool
  -> Int
  -> IO (Either String ())
softDeleteOccurrence pool reqUid isAdmin oidInt = do
  let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
  mo <- runSqlPool (get oid) pool
  case mo of
    Nothing -> return $ Left "occurrence not found"
    Just o
      | E.occurrenceDeletedAt o /= Nothing -> return $ Left "occurrence not found"
      | not isAdmin && E.occurrenceUserId o /= reqUid -> return $ Left "forbidden"
      | otherwise -> do
          now <- getCurrentTime
          runSqlPool (update oid [E.OccurrenceDeletedAt =. Just now]) pool
          Logs.logInfo $ "occurrence " ++ show oidInt ++ " soft-deleted by user " ++ show (fromSqlKey reqUid)
          return $ Right ()

-- | Hard delete: apaga do banco junto com votos e comentários. Apenas admin.
hardDeleteOccurrence
  :: ConnectionPool
  -> Int
  -> IO (Either String ())
hardDeleteOccurrence pool oidInt = do
  let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
  mo <- runSqlPool (get oid) pool
  case mo of
    Nothing -> return $ Left "occurrence not found"
    Just _  -> do
      runSqlPool (deleteWhere [E.VoteOccurrenceId ==. oid]) pool
      runSqlPool (deleteWhere [E.CommentOccurrenceId ==. oid]) pool
      runSqlPool (delete oid) pool
      Logs.logInfo $ "occurrence " ++ show oidInt ++ " HARD-deleted"
      return $ Right ()

-- | Geo-search: retorna ocorrências dentro de `radiusKm` do ponto, ordenadas
-- por distância crescente. Usa Haversine em Haskell (dataset pequeno o
-- suficiente — para escala maior, usar PostGIS).
nearbyOccurrences
  :: ConnectionPool
  -> Double   -- ^ lat do ponto
  -> Double   -- ^ lng do ponto
  -> Double   -- ^ raio em km
  -> Int      -- ^ limit (cap)
  -> IO [D.NearbyOccurrenceDto]
nearbyOccurrences pool lat lng radiusKm lim = do
  occs <- runSqlPool (selectList notDeleted []) pool
  let withDist =
        [ (e, d)
        | e@(Entity _ o) <- occs
        , Just la <- [E.occurrenceLatitude  o]
        , Just lo <- [E.occurrenceLongitude o]
        , let d = haversineKm lat lng la lo
        , d <= radiusKm
        ]
      sorted = take lim (sortOn snd withDist)
  mapM (\(e, d) -> do
    dto <- attachVoteCount pool e
    return (D.NearbyOccurrenceDto dto d)
    ) sorted

-- Helpers ------------------------------------------------------------

-- | Haversine: distância em km entre dois pares lat/lng.
haversineKm :: Double -> Double -> Double -> Double -> Double
haversineKm lat1 lng1 lat2 lng2 =
  let r   = 6371.0
      toRad x = x * pi / 180
      dLat = toRad (lat2 - lat1)
      dLng = toRad (lng2 - lng1)
      a    = sin (dLat / 2) ** 2
           + cos (toRad lat1) * cos (toRad lat2) * sin (dLng / 2) ** 2
      c    = 2 * atan2 (sqrt a) (sqrt (1 - a))
  in r * c

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

resolveLocation
  :: E.User
  -> Maybe String
  -> IO (String, String, String)
resolveLocation u Nothing =
  return (E.userCep u, E.userCity u, E.userUf u)
resolveLocation u (Just cepStr) = do
  res <- Apis.fetchCep cepStr
  case res of
    Left _   -> return (E.userCep u, E.userCity u, E.userUf u)
    Right vc -> return
      ( cepStr
      , fromMaybe (E.userCity u) (Apis.localidade vc)
      , fromMaybe (E.userUf u)   (Apis.uf vc)
      )
