{-# LANGUAGE OverloadedStrings #-}

-- | Casos de uso de Politician e Mandate: criar e listar.
module UseCase.MandateCase
  ( createPolitician
  , createMandate
  , listMandates
  , politicianToDto
  , mandateToDto
  ) where

import Database.Persist (Entity(..), get, insert, selectList)
import Database.Persist.Sql (ConnectionPool, runSqlPool, fromSqlKey, toSqlKey)

import qualified Dto.MandateDto as D
import qualified Repository.Entities as E
import qualified InterfaceAdapters.Logs as Logs

-- ------- Politician

createPolitician
  :: ConnectionPool
  -> D.CreatePoliticianDto
  -> IO D.PoliticianResponseDto
createPolitician pool dto = do
  let p = E.Politician
            { E.politicianName  = D.polName dto
            , E.politicianParty = D.polParty dto
            , E.politicianRole  = D.polRole dto
            }
  pid <- runSqlPool (insert p) pool
  Logs.logInfo $ "politician created: " ++ D.polName dto
  return D.PoliticianResponseDto
    { D.politicianId    = fromSqlKey pid
    , D.politicianName  = D.polName dto
    , D.politicianParty = D.polParty dto
    , D.politicianRole  = D.polRole dto
    }

-- ------- Mandate

createMandate
  :: ConnectionPool
  -> D.CreateMandateDto
  -> IO (Either String D.MandateResponseDto)
createMandate pool dto = do
  let pid = toSqlKey (D.manPoliticianId dto) :: E.PoliticianId
  mp <- runSqlPool (get pid) pool
  case mp of
    Nothing -> return $ Left "politician not found"
    Just p  -> do
      let m = E.Mandate
                { E.mandatePoliticianId = pid
                , E.mandateCity         = D.manCity dto
                , E.mandateUf           = D.manUf dto
                , E.mandateStartDate    = D.manStartDate dto
                , E.mandateEndDate      = D.manEndDate dto
                }
      mid <- runSqlPool (insert m) pool
      Logs.logInfo $ "mandate created for politician " ++ show (fromSqlKey pid)
      return $ Right (mandateToDto (Entity mid m) (Entity pid p))

listMandates :: ConnectionPool -> IO [D.MandateResponseDto]
listMandates pool = do
  ms <- runSqlPool (selectList [] []) pool
  mapM (\(Entity mid m) -> do
          mp <- runSqlPool (get (E.mandatePoliticianId m)) pool
          case mp of
            Nothing -> return (mandateToDto (Entity mid m)
                                            (Entity (E.mandatePoliticianId m)
                                                    (E.Politician "?" "?" "?")))
            Just p  -> return (mandateToDto (Entity mid m)
                                            (Entity (E.mandatePoliticianId m) p))
       ) ms

-- ------- helpers

politicianToDto :: Entity E.Politician -> D.PoliticianResponseDto
politicianToDto (Entity pid p) = D.PoliticianResponseDto
  { D.politicianId    = fromSqlKey pid
  , D.politicianName  = E.politicianName p
  , D.politicianParty = E.politicianParty p
  , D.politicianRole  = E.politicianRole p
  }

mandateToDto :: Entity E.Mandate -> Entity E.Politician -> D.MandateResponseDto
mandateToDto (Entity mid m) entP = D.MandateResponseDto
  { D.mandateId        = fromSqlKey mid
  , D.mandatePolitician = politicianToDto entP
  , D.mandateCity      = E.mandateCity m
  , D.mandateUf        = E.mandateUf m
  , D.mandateStartDate = E.mandateStartDate m
  , D.mandateEndDate   = E.mandateEndDate m
  }
