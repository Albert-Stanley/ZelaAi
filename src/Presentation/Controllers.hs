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
  -- novos
  , updateOccurrenceController
  , deleteOccurrenceController
  , nearbyOccurrencesController
  , createCommentController
  , listCommentsController
  , editCommentController
  , deleteCommentController
  , listMyCommentsController
  , adminListUsersController
  , adminSetUserRoleController
  , adminStatsController
  , adminDeleteOccurrenceController
  ) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.Text as T
import Data.Int (Int64)
import Database.Persist.Sql (ConnectionPool)
import Servant (Handler, NoContent(..), throwError)

import qualified Dto.UserDto as D
import qualified Dto.CategoryDto as C
import qualified Dto.OccurrenceDto as O
import qualified Dto.VoteDto as V
import qualified Dto.MandateDto as M
import qualified Dto.CommentDto as Cm
import qualified Validation.UserValidation as UV
import qualified Validation.OccurrenceValidation as OV
import qualified Validation.MandateValidation as MV
import qualified UseCase.UserCase as UC
import qualified UseCase.CategoryCase as CC
import qualified UseCase.OccurrenceCase as OC
import qualified UseCase.VoteCase as VC
import qualified UseCase.MandateCase as MC
import qualified UseCase.ScoreCase as SC
import qualified UseCase.CommentCase as CmC
import qualified UseCase.AdminCase as AC
import qualified Repository.Entities as E
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

-- GET /occurrences?page=&pageSize=
listOccurrencesController
  :: ConnectionPool
  -> Maybe Int
  -> Maybe Int
  -> Handler [O.OccurrenceResponseDto]
listOccurrencesController pool mPage mSize =
  liftIO $ OC.listOccurrences pool mPage mSize

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

-- GET /users/me/occurrences?page=&pageSize= (JWT)
listMyOccurrencesController
  :: ConnectionPool
  -> Maybe T.Text
  -> Maybe Int
  -> Maybe Int
  -> Handler [O.OccurrenceResponseDto]
listMyOccurrencesController pool authHeader mPage mSize = do
  uid <- Auth.extractUserId authHeader
  liftIO $ OC.listMyOccurrences pool uid mPage mSize

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

-- =================================================================
-- Endpoints novos: edit/delete de ocorrencia, nearby, comments, admin
-- =================================================================

-- | Resolve um userId vindo do JWT em (uid, isAdmin).
authedAdmin :: ConnectionPool -> Maybe T.Text -> Handler (E.UserId, Bool)
authedAdmin pool h = do
  uid     <- Auth.extractUserId h
  isA     <- liftIO $ AC.isAdmin pool uid
  return (uid, isA)

-- | Garante que o usuário do JWT é admin; senão lança 403.
requireAdmin :: ConnectionPool -> Maybe T.Text -> Handler E.UserId
requireAdmin pool h = do
  (uid, isA) <- authedAdmin pool h
  if isA then return uid else throwError (Err.forbidden "admin only")

-- PATCH /occurrences/:id  (JWT, dono ou admin)
updateOccurrenceController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> O.UpdateOccurrenceDto
  -> Handler O.OccurrenceResponseDto
updateOccurrenceController pool h oid dto = do
  (uid, isA) <- authedAdmin pool h
  result <- liftIO $ OC.updateOccurrence pool uid isA (fromIntegral oid) dto
  case result of
    Left "occurrence not found" -> throwError (Err.notFound "occurrence not found")
    Left "forbidden"            -> throwError (Err.forbidden "not your occurrence")
    Left err                    -> throwError (Err.badRequest err)
    Right ok                    -> return ok

-- DELETE /occurrences/:id  (JWT, dono ou admin = soft delete)
deleteOccurrenceController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> Handler NoContent
deleteOccurrenceController pool h oid = do
  (uid, isA) <- authedAdmin pool h
  result <- liftIO $ OC.softDeleteOccurrence pool uid isA (fromIntegral oid)
  case result of
    Left "occurrence not found" -> throwError (Err.notFound "occurrence not found")
    Left "forbidden"            -> throwError (Err.forbidden "not your occurrence")
    Left err                    -> throwError (Err.badRequest err)
    Right ()                    -> return NoContent

-- GET /occurrences/nearby?lat=...&lng=...&radiusKm=...
nearbyOccurrencesController
  :: ConnectionPool
  -> Maybe Double
  -> Maybe Double
  -> Maybe Double
  -> Handler [O.NearbyOccurrenceDto]
nearbyOccurrencesController pool mlat mlng mradius =
  case (mlat, mlng) of
    (Just lat, Just lng) ->
      let r = maybe 5.0 (min 50 . max 0.1) mradius   -- clamp 0.1..50 km
      in liftIO $ OC.nearbyOccurrences pool lat lng r 50
    _ -> throwError (Err.badRequest "lat and lng query params are required")

-- POST /occurrences/:id/comments  (JWT)
createCommentController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> Cm.CreateCommentDto
  -> Handler Cm.CommentResponseDto
createCommentController pool h oid dto = do
  uid <- Auth.extractUserId h
  result <- liftIO $ CmC.createComment pool uid (fromIntegral oid) (Cm.newCommentBody dto)
  case result of
    Left "occurrence not found" -> throwError (Err.notFound "occurrence not found")
    Left err                    -> throwError (Err.badRequest err)
    Right ok                    -> return ok

-- GET /occurrences/:id/comments?page=&pageSize=
listCommentsController
  :: ConnectionPool
  -> Int64
  -> Maybe Int
  -> Maybe Int
  -> Handler [Cm.CommentResponseDto]
listCommentsController pool oid mPage mSize =
  liftIO $ CmC.listCommentsByOccurrence pool (fromIntegral oid) mPage mSize

-- PATCH /comments/:id  (JWT, apenas autor)
editCommentController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> Cm.UpdateCommentDto
  -> Handler Cm.CommentResponseDto
editCommentController pool h cid dto = do
  uid <- Auth.extractUserId h
  result <- liftIO $ CmC.editComment pool uid (fromIntegral cid) (Cm.updCommentBody dto)
  case result of
    Left "comment not found" -> throwError (Err.notFound "comment not found")
    Left "forbidden"         -> throwError (Err.forbidden "not your comment")
    Left err                 -> throwError (Err.badRequest err)
    Right ok                 -> return ok

-- DELETE /comments/:id  (JWT, autor ou admin)
deleteCommentController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> Handler NoContent
deleteCommentController pool h cid = do
  (uid, isA) <- authedAdmin pool h
  result <- liftIO $ CmC.deleteComment pool uid isA (fromIntegral cid)
  case result of
    Left "comment not found" -> throwError (Err.notFound "comment not found")
    Left "forbidden"         -> throwError (Err.forbidden "not your comment")
    Left err                 -> throwError (Err.badRequest err)
    Right ()                 -> return NoContent

-- GET /users/me/comments?page=&pageSize= (JWT)
listMyCommentsController
  :: ConnectionPool
  -> Maybe T.Text
  -> Maybe Int
  -> Maybe Int
  -> Handler [Cm.CommentResponseDto]
listMyCommentsController pool h mPage mSize = do
  uid <- Auth.extractUserId h
  liftIO $ CmC.listMyComments pool uid mPage mSize

-- GET /admin/users  (JWT + admin)
adminListUsersController
  :: ConnectionPool
  -> Maybe T.Text
  -> Handler [D.UserResponseDto]
adminListUsersController pool h = do
  _ <- requireAdmin pool h
  liftIO $ AC.listAllUsers pool

-- PATCH /admin/users/:id/role  (JWT + admin)
adminSetUserRoleController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> D.SetRoleDto
  -> Handler D.UserResponseDto
adminSetUserRoleController pool h uid body = do
  _ <- requireAdmin pool h
  result <- liftIO $ AC.setUserRole pool (fromIntegral uid) (D.role body)
  case result of
    Left "user not found" -> throwError (Err.notFound "user not found")
    Left err              -> throwError (Err.badRequest err)
    Right ok              -> return ok

-- GET /admin/stats  (JWT + admin)
adminStatsController
  :: ConnectionPool
  -> Maybe T.Text
  -> Handler AC.AdminStatsDto
adminStatsController pool h = do
  _ <- requireAdmin pool h
  liftIO $ AC.adminStats pool

-- DELETE /admin/occurrences/:id  (JWT + admin = hard delete)
adminDeleteOccurrenceController
  :: ConnectionPool
  -> Maybe T.Text
  -> Int64
  -> Handler NoContent
adminDeleteOccurrenceController pool h oid = do
  _ <- requireAdmin pool h
  result <- liftIO $ OC.hardDeleteOccurrence pool (fromIntegral oid)
  case result of
    Left "occurrence not found" -> throwError (Err.notFound "occurrence not found")
    Left err                    -> throwError (Err.badRequest err)
    Right ()                    -> return NoContent
