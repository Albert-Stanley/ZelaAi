{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Definicao do tipo da API e do server. MyLib.hs apenas chama startApp.
module Api
  ( API
  , app
  , server
  ) where

import Control.Exception (try, SomeException)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT)
import Data.Aeson (ToJSON)
import qualified Data.Text as T
import Data.Int (Int64)
import Data.Time.Clock (getCurrentTime)
import GHC.Generics (Generic)
import Servant
import Database.Persist.Sql (ConnectionPool, Single, SqlBackend, rawSql, runSqlPool)

import qualified Dto.UserDto as D
import qualified Dto.CategoryDto as C
import qualified Dto.OccurrenceDto as O
import qualified Dto.VoteDto as V
import qualified Dto.MandateDto as M
import qualified Dto.CommentDto as Cm
import qualified UseCase.AdminCase as AC
import qualified Presentation.Controllers as Ctrl

-- Health
data Hello = Hello { mensagem :: String } deriving (Generic, ToJSON)

helloHandler :: Handler Hello
helloHandler = return (Hello "ZelaAi no ar")

-- | Healthcheck para Render/Docker. Faz um SELECT 1 no Postgres para garantir
-- que a aplicação + banco estão respondendo. Retorna 503 se o DB falhar.
data HealthStatus = HealthStatus
  { status  :: String   -- "ok" | "degraded"
  , db      :: String   -- "ok" | "down"
  , service :: String   -- "ZelaAi"
  , version :: String   -- semver
  , time    :: String   -- ISO 8601
  } deriving (Generic, ToJSON)

healthHandler :: ConnectionPool -> Handler HealthStatus
healthHandler pool = do
  now <- liftIO getCurrentTime
  dbOk <- liftIO $ do
    let ping = rawSql "SELECT 1" [] :: ReaderT SqlBackend IO [Single Int]
    r <- try (runSqlPool ping pool) :: IO (Either SomeException [Single Int])
    return $ case r of Right _ -> True; Left _ -> False
  let payload = HealthStatus
        { status  = if dbOk then "ok" else "degraded"
        , db      = if dbOk then "ok" else "down"
        , service = "ZelaAi"
        , version = "0.1.0"
        , time    = show now
        }
  if dbOk
    then return payload
    else throwError err503 { errBody = "{\"status\":\"degraded\",\"db\":\"down\"}" }

type API =
       Get '[JSON] Hello
  :<|> "health" :> Get '[JSON] HealthStatus

  -- Users
  :<|> "users" :> "register" :> ReqBody '[JSON] D.RegisterUserDto :> Post '[JSON] D.UserResponseDto
  :<|> "users" :> "login"    :> ReqBody '[JSON] D.LoginUserDto    :> Post '[JSON] D.LoginResponseDto
  :<|> "users" :> "me" :> "occurrences"
        :> Header "Authorization" T.Text
        :> QueryParam "page"     Int
        :> QueryParam "pageSize" Int
        :> Get '[JSON] [O.OccurrenceResponseDto]

  -- Categories
  :<|> "categories" :> Get '[JSON] [C.CategoryResponseDto]

  -- Occurrences
  :<|> "occurrences"
        :> "by-location"
        :> QueryParam "cep" String
        :> Get '[JSON] [O.OccurrenceResponseDto]
  :<|> "occurrences"
        :> Capture "id" Int64
        :> "vote"
        :> Header "Authorization" T.Text
        :> Post '[JSON] V.VoteResponseDto
  :<|> "occurrences"
        :> Capture "id" Int64
        :> "vote"
        :> Header "Authorization" T.Text
        :> Delete '[JSON] V.VoteResponseDto
  :<|> "occurrences"
        :> Capture "id" Int64
        :> "status"
        :> Header "Authorization" T.Text
        :> ReqBody '[JSON] O.UpdateStatusDto
        :> Patch '[JSON] O.OccurrenceResponseDto
  :<|> "occurrences"
        :> Capture "id" Int64
        :> Get '[JSON] O.OccurrenceResponseDto
  :<|> "occurrences"
        :> Header "Authorization" T.Text
        :> ReqBody '[JSON] O.CreateOccurrenceDto
        :> Post '[JSON] O.OccurrenceResponseDto
  :<|> "occurrences"
        :> QueryParam "page"     Int
        :> QueryParam "pageSize" Int
        :> Get '[JSON] [O.OccurrenceResponseDto]

  -- Politicians
  :<|> "politicians"
        :> ReqBody '[JSON] M.CreatePoliticianDto
        :> Post '[JSON] M.PoliticianResponseDto

  -- Mandates
  :<|> "mandates"
        :> Capture "id" Int64
        :> "score"
        :> Get '[JSON] M.ScoreResponseDto
  :<|> "mandates"
        :> ReqBody '[JSON] M.CreateMandateDto
        :> Post '[JSON] M.MandateResponseDto
  :<|> "mandates" :> Get '[JSON] [M.MandateResponseDto]

  -- Occurrences: edit/delete + geo
  :<|> "occurrences"
        :> Capture "id" Int64
        :> Header "Authorization" T.Text
        :> ReqBody '[JSON] O.UpdateOccurrenceDto
        :> Patch '[JSON] O.OccurrenceResponseDto
  :<|> "occurrences"
        :> Capture "id" Int64
        :> Header "Authorization" T.Text
        :> Delete '[JSON] NoContent
  :<|> "occurrences"
        :> "nearby"
        :> QueryParam "lat"      Double
        :> QueryParam "lng"      Double
        :> QueryParam "radiusKm" Double
        :> Get '[JSON] [O.NearbyOccurrenceDto]

  -- Comments
  :<|> "occurrences"
        :> Capture "id" Int64
        :> "comments"
        :> Header "Authorization" T.Text
        :> ReqBody '[JSON] Cm.CreateCommentDto
        :> Post '[JSON] Cm.CommentResponseDto
  :<|> "occurrences"
        :> Capture "id" Int64
        :> "comments"
        :> QueryParam "page"     Int
        :> QueryParam "pageSize" Int
        :> Get '[JSON] [Cm.CommentResponseDto]
  :<|> "comments"
        :> Capture "id" Int64
        :> Header "Authorization" T.Text
        :> Delete '[JSON] NoContent
  :<|> "comments"
        :> Capture "id" Int64
        :> Header "Authorization" T.Text
        :> ReqBody '[JSON] Cm.UpdateCommentDto
        :> Patch '[JSON] Cm.CommentResponseDto
  :<|> "users" :> "me" :> "comments"
        :> Header "Authorization" T.Text
        :> QueryParam "page"     Int
        :> QueryParam "pageSize" Int
        :> Get '[JSON] [Cm.CommentResponseDto]

  -- Admin
  :<|> "admin" :> "users"
        :> Header "Authorization" T.Text
        :> Get '[JSON] [D.UserResponseDto]
  :<|> "admin" :> "users"
        :> Capture "id" Int64
        :> "role"
        :> Header "Authorization" T.Text
        :> ReqBody '[JSON] D.SetRoleDto
        :> Patch '[JSON] D.UserResponseDto
  :<|> "admin" :> "stats"
        :> Header "Authorization" T.Text
        :> Get '[JSON] AC.AdminStatsDto
  :<|> "admin" :> "occurrences"
        :> Capture "id" Int64
        :> Header "Authorization" T.Text
        :> Delete '[JSON] NoContent

server :: ConnectionPool -> Server API
server pool =
       helloHandler
  :<|> healthHandler pool
  :<|> Ctrl.registerController pool
  :<|> Ctrl.loginController pool
  :<|> (\auth mp ms -> Ctrl.listMyOccurrencesController pool auth mp ms)
  :<|> Ctrl.listCategoriesController pool
  :<|> Ctrl.listOccurrencesByCepController pool
  :<|> (\oid auth -> Ctrl.voteController pool auth oid)
  :<|> (\oid auth -> Ctrl.unvoteController pool auth oid)
  :<|> (\oid auth dto -> Ctrl.updateStatusController pool auth oid dto)
  :<|> Ctrl.getOccurrenceController pool
  :<|> Ctrl.createOccurrenceController pool
  :<|> (\mp ms -> Ctrl.listOccurrencesController pool mp ms)
  :<|> Ctrl.createPoliticianController pool
  :<|> Ctrl.mandateScoreController pool
  :<|> Ctrl.createMandateController pool
  :<|> Ctrl.listMandatesController pool
  :<|> (\oid auth dto -> Ctrl.updateOccurrenceController pool auth oid dto)
  :<|> (\oid auth     -> Ctrl.deleteOccurrenceController pool auth oid)
  :<|> Ctrl.nearbyOccurrencesController pool
  :<|> (\oid auth dto -> Ctrl.createCommentController pool auth oid dto)
  :<|> (\oid mp ms -> Ctrl.listCommentsController pool oid mp ms)
  :<|> (\cid auth     -> Ctrl.deleteCommentController pool auth cid)
  :<|> (\cid auth dto -> Ctrl.editCommentController pool auth cid dto)
  :<|> (\auth mp ms -> Ctrl.listMyCommentsController pool auth mp ms)
  :<|> Ctrl.adminListUsersController pool
  :<|> (\uid auth dto -> Ctrl.adminSetUserRoleController pool auth uid dto)
  :<|> Ctrl.adminStatsController pool
  :<|> (\oid auth     -> Ctrl.adminDeleteOccurrenceController pool auth oid)

app :: ConnectionPool -> Application
app pool = serve (Proxy :: Proxy API) (server pool)
