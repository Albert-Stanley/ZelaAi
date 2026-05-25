{-# LANGUAGE OverloadedStrings #-}

-- | Controllers HTTP. Cada handler segue o padrao do TCC:
--   Deserialize (Servant ja faz) -> Validate -> UseCase -> 200 / 4xx.
module Presentation.Controllers
  ( registerController
  , loginController
  , listCategoriesController
  , createOccurrenceController
  , listOccurrencesController
  , getOccurrenceController
  , listOccurrencesByCepController
  , updateStatusController
  , listMyOccurrencesController
  , voteController
  , unvoteController
  , createPoliticianController
  , createMandateController
  , listMandatesController
  , mandateScoreController
  ) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.Text as T
import Data.Int (Int64)
import Database.Persist.Sql (ConnectionPool)
import Servant (Handler, throwError)

import qualified Dto.UserDto as D
import qualified Dto.CategoryDto as C
import qualified Dto.OccurrenceDto as O
import qualified Dto.VoteDto as V
import qualified Dto.MandateDto as M
import qualified Validation.UserValidation as UV
import qualified Validation.OccurrenceValidation as OV
import qualified Validation.MandateValidation as MV
import qualified UseCase.UserCase as UC
import qualified UseCase.CategoryCase as CC
import qualified UseCase.OccurrenceCase as OC
import qualified UseCase.VoteCase as VC
import qualified UseCase.MandateCase as MC
import qualified UseCase.ScoreCase as SC
import qualified Presentation.Errors as Err
import qualified Presentation.Auth as Auth

-- POST /users/register
registerController :: ConnectionPool -> D.RegisterUserDto -> Handler D.UserResponseDto
registerController pool dto =
  case UV.validateRegister dto of
    Left err -> throwError (Err.badRequest err)
    Right valid -> do
      result <- liftIO $ UC.registerUser pool valid
      case result of
        Left err -> throwError (Err.badRequest err)
        Right ok -> return ok

-- POST /users/login
loginController :: ConnectionPool -> D.LoginUserDto -> Handler D.LoginResponseDto
loginController pool dto =
  case UV.validateLogin dto of
    Left err -> throwError (Err.badRequest err)
    Right valid -> do
      result <- liftIO $ UC.loginUser pool valid
      case result of
        Left err -> throwError (Err.unauthorized err)
        Right ok -> return ok

-- GET /categories
listCategoriesController :: ConnectionPool -> Handler [C.CategoryResponseDto]
listCategoriesController pool = liftIO $ CC.listCategories pool

-- POST /occurrences  (JWT obrigatorio)
createOccurrenceController
  :: ConnectionPool
  -> Maybe T.Text                       -- header Authorization
  -> O.CreateOccurrenceDto
  -> Handler O.OccurrenceResponseDto
createOccurrenceController pool authHeader dto = do
  uid <- Auth.extractUserId authHeader
  case OV.validateCreate dto of
    Left err -> throwError (Err.badRequest err)
    Right valid -> do
      result <- liftIO $ OC.createOccurrence pool uid valid
      case result of
        Left err -> throwError (Err.badRequest err)
        Right ok -> return ok

-- GET /occurrences
listOccurrencesController :: ConnectionPool -> Handler [O.OccurrenceResponseDto]
listOccurrencesController pool = liftIO $ OC.listOccurrences pool

-- GET /occurrences/:id
getOccurrenceController :: ConnectionPool -> Int64 -> Handler O.OccurrenceResponseDto
getOccurrenceController pool oid = do
  mr <- liftIO $ OC.getOccurrence pool (fromIntegral oid)
  case mr of
    Nothing -> throwError (Err.notFound "occurrence not found")
    Just r  -> return r

-- GET /occurrences/by-location?cep=...
listOccurrencesByCepController
  :: ConnectionPool
  -> Maybe String
  -> Handler [O.OccurrenceResponseDto]
listOccurrencesByCepController pool mcep =
  case mcep of
    Nothing  -> throwError (Err.badRequest "cep query param is required")
    Just cep -> liftIO $ OC.listByCep pool cep

-- PATCH /occurrences/:id/status (JWT)
updateStatusController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> O.UpdateStatusDto
  -> Handler O.OccurrenceResponseDto
updateStatusController pool authHeader oid dto = do
  _uid <- Auth.extractUserId authHeader
  result <- liftIO $ OC.updateStatus pool (fromIntegral oid) (O.newStatus dto)
  case result of
    Left "occurrence not found" -> throwError (Err.notFound "occurrence not found")
    Left err                    -> throwError (Err.badRequest err)
    Right ok                    -> return ok

-- GET /users/me/occurrences (JWT)
listMyOccurrencesController
  :: ConnectionPool
  -> Maybe T.Text
  -> Handler [O.OccurrenceResponseDto]
listMyOccurrencesController pool authHeader = do
  uid <- Auth.extractUserId authHeader
  liftIO $ OC.listMyOccurrences pool uid

-- POST /occurrences/:id/vote (JWT)
voteController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> Handler V.VoteResponseDto
voteController pool authHeader oid = do
  uid <- Auth.extractUserId authHeader
  result <- liftIO $ VC.voteOccurrence pool uid (fromIntegral oid)
  case result of
    Left "occurrence not found" -> throwError (Err.notFound "occurrence not found")
    Left "already voted"        -> throwError (Err.conflict "already voted")
    Left err                    -> throwError (Err.badRequest err)
    Right ok                    -> return ok

-- DELETE /occurrences/:id/vote (JWT)
unvoteController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> Handler V.VoteResponseDto
unvoteController pool authHeader oid = do
  uid <- Auth.extractUserId authHeader
  result <- liftIO $ VC.unvoteOccurrence pool uid (fromIntegral oid)
  case result of
    Left "occurrence not found" -> throwError (Err.notFound "occurrence not found")
    Left "vote not found"       -> throwError (Err.notFound "vote not found")
    Left err                    -> throwError (Err.badRequest err)
    Right ok                    -> return ok

-- POST /politicians
createPoliticianController
  :: ConnectionPool
  -> M.CreatePoliticianDto
  -> Handler M.PoliticianResponseDto
createPoliticianController pool dto =
  case MV.validatePolitician dto of
    Left err    -> throwError (Err.badRequest err)
    Right valid -> liftIO $ MC.createPolitician pool valid

-- POST /mandates
createMandateController
  :: ConnectionPool
  -> M.CreateMandateDto
  -> Handler M.MandateResponseDto
createMandateController pool dto =
  case MV.validateMandate dto of
    Left err -> throwError (Err.badRequest err)
    Right valid -> do
      result <- liftIO $ MC.createMandate pool valid
      case result of
        Left err -> throwError (Err.badRequest err)
        Right ok -> return ok

-- GET /mandates
listMandatesController
  :: ConnectionPool
  -> Handler [M.MandateResponseDto]
listMandatesController pool = liftIO $ MC.listMandates pool

-- GET /mandates/:id/score
mandateScoreController
  :: ConnectionPool
  -> Int64
  -> Handler M.ScoreResponseDto
mandateScoreController pool mid = do
  mr <- liftIO $ SC.calculateScore pool (fromIntegral mid)
  case mr of
    Nothing -> throwError (Err.notFound "mandate not found")
    Just r  -> return r
