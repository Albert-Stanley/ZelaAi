{-# LANGUAGE OverloadedStrings #-}

-- | Casos de uso de User: registro e login.
module UseCase.UserCase
  ( registerUser
  , loginUser
  ) where

import Data.Time (getCurrentTime)
import Data.Maybe (fromMaybe)
import Database.Persist (Entity(..), getBy, selectFirst)
import Database.Persist.Sql (ConnectionPool, runSqlPool, fromSqlKey, insert, (==.))

import qualified Dto.UserDto as D
import qualified Repository.Entities as E
import qualified InterfaceAdapters.Libs as Libs
import qualified InterfaceAdapters.Apis as Apis
import qualified InterfaceAdapters.Logs as Logs

-- | Pos-validacao do DTO: consulta ViaCEP, hash de senha, persiste no Postgres.
registerUser :: ConnectionPool -> D.RegisterUserDto -> IO (Either String D.UserResponseDto)
registerUser pool dto = do
  -- 1) ViaCEP
  via <- Apis.fetchCep (D.cep dto)
  case via of
    Left err -> do
      Logs.logError $ "ViaCEP fail: " ++ err
      return $ Left ("invalid cep: " ++ err)
    Right vc -> do
      let city = fromMaybe "" (Apis.localidade vc)
          uf   = fromMaybe "" (Apis.uf vc)
      -- 2) checa duplicata
      existing <- runSqlPool (getBy (E.UniqueUsername (D.username dto))) pool
      case existing of
        Just _ -> return $ Left "username already taken"
        Nothing -> do
          -- 3) hash + persist
          hashed <- Libs.hashPassword (D.password dto)
          now    <- getCurrentTime
          let user = E.User
                       { E.userName      = D.name dto
                       , E.userUsername  = D.username dto
                       , E.userPassword  = hashed
                       , E.userCep       = D.cep dto
                       , E.userCity      = city
                       , E.userUf        = uf
                       , E.userCreatedAt = now
                       }
          newKey <- runSqlPool (insert user) pool
          Logs.logInfo $ "user registered: " ++ D.username dto
          return $ Right D.UserResponseDto
            { D.userId       = fromSqlKey newKey
            , D.userName     = D.name dto
            , D.userUsername = D.username dto
            , D.userCep      = D.cep dto
            , D.userCity     = city
            , D.userUf       = uf
            }

-- | Login: busca por username, valida bcrypt, gera JWT.
loginUser :: ConnectionPool -> D.LoginUserDto -> IO (Either String D.LoginResponseDto)
loginUser pool dto = do
  mu <- runSqlPool (selectFirst [E.UserUsername ==. D.loginUsername dto] []) pool
  case mu of
    Nothing -> return $ Left "invalid credentials"
    Just (Entity uid u) ->
      if not (Libs.verifyPassword (D.loginPassword dto) (E.userPassword u))
        then return $ Left "invalid credentials"
        else do
          let uidInt = fromSqlKey uid
          tok <- Libs.generateTokenJwt uidInt
          Logs.logInfo $ "login ok: " ++ D.loginUsername dto
          return $ Right D.LoginResponseDto
            { D.token = tok
            , D.user  = D.UserResponseDto
                { D.userId       = uidInt
                , D.userName     = E.userName u
                , D.userUsername = E.userUsername u
                , D.userCep      = E.userCep u
                , D.userCity     = E.userCity u
                , D.userUf       = E.userUf u
                }
            }
