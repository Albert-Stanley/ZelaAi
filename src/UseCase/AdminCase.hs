{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- | Casos de uso administrativos. Todos requerem role=admin (a checagem
-- acontece no controller via 'requireAdmin').
module UseCase.AdminCase
  ( isAdmin
  , listAllUsers
  , setUserRole
  , adminStats
  , AdminStatsDto(..)
  ) where

import Database.Persist (Entity(..), Filter, get, selectList, update, count, (=.), (==.), (!=.))
import Database.Persist.Sql (ConnectionPool, runSqlPool, fromSqlKey, toSqlKey)
import GHC.Generics (Generic)
import Data.Aeson (ToJSON)

import qualified Repository.Entities as E
import qualified Dto.UserDto as UD
import qualified InterfaceAdapters.Logs as Logs

-- | Helper: o user com este id é admin?
isAdmin :: ConnectionPool -> E.UserId -> IO Bool
isAdmin pool uid = do
  mu <- runSqlPool (get uid) pool
  return $ case mu of
    Just u  -> E.userRole u == "admin"
    Nothing -> False

-- | Lista todos os usuários (sem o hash de senha).
listAllUsers :: ConnectionPool -> IO [UD.UserResponseDto]
listAllUsers pool = do
  rows <- runSqlPool (selectList ([] :: [Filter E.User]) []) pool
  return $ map entToDto rows

-- | Altera o role de um user. Valida valores válidos.
setUserRole :: ConnectionPool -> Int -> String -> IO (Either String UD.UserResponseDto)
setUserRole pool uidInt newRole
  | newRole `notElem` ["citizen", "admin"] = return $ Left "invalid role"
  | otherwise = do
      let uid = toSqlKey (fromIntegral uidInt) :: E.UserId
      mu <- runSqlPool (get uid) pool
      case mu of
        Nothing -> return $ Left "user not found"
        Just _  -> do
          runSqlPool (update uid [E.UserRole =. newRole]) pool
          Logs.logInfo $ "admin: user " ++ show uidInt ++ " role -> " ++ newRole
          mu' <- runSqlPool (get uid) pool
          case mu' of
            Nothing -> return $ Left "user vanished"
            Just u  -> return $ Right (entToDto (Entity uid u))

-- | Estatísticas administrativas: contagens totais.
data AdminStatsDto = AdminStatsDto
  { adminUsers       :: Int
  , adminAdmins      :: Int
  , adminOccurrences :: Int      -- ativas
  , adminDeleted     :: Int      -- soft-deleted
  , adminVotes       :: Int
  , adminComments    :: Int
  , adminMandates    :: Int
  } deriving (Generic, Show, ToJSON)

adminStats :: ConnectionPool -> IO AdminStatsDto
adminStats pool = do
  totalUsers <- runSqlPool (count ([] :: [Filter E.User]))       pool
  admins     <- runSqlPool (count [E.UserRole ==. "admin"])      pool
  liveOccs   <- runSqlPool (count [E.OccurrenceDeletedAt ==. Nothing]) pool
  delOccs    <- runSqlPool (count [E.OccurrenceDeletedAt !=. Nothing]) pool
  votes      <- runSqlPool (count ([] :: [Filter E.Vote]))       pool
  comments   <- runSqlPool (count ([] :: [Filter E.Comment]))    pool
  mandates   <- runSqlPool (count ([] :: [Filter E.Mandate]))    pool
  return AdminStatsDto
    { adminUsers       = totalUsers
    , adminAdmins      = admins
    , adminOccurrences = liveOccs
    , adminDeleted     = delOccs
    , adminVotes       = votes
    , adminComments    = comments
    , adminMandates    = mandates
    }

entToDto :: Entity E.User -> UD.UserResponseDto
entToDto (Entity uid u) = UD.UserResponseDto
  { UD.userId       = fromSqlKey uid
  , UD.userName     = E.userName u
  , UD.userUsername = E.userUsername u
  , UD.userCep      = E.userCep u
  , UD.userCity     = E.userCity u
  , UD.userUf       = E.userUf u
  , UD.userRole     = E.userRole u
  }
