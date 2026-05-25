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

import Data.Aeson (ToJSON)
import qualified Data.Text as T
import Data.Int (Int64)
import GHC.Generics (Generic)
import Servant
import Database.Persist.Sql (ConnectionPool)

import qualified Dto.UserDto as D
import qualified Dto.CategoryDto as C
import qualified Dto.OccurrenceDto as O
import qualified Dto.VoteDto as V
import qualified Dto.MandateDto as M
import qualified Presentation.Controllers as Ctrl

-- Health
data Hello = Hello { mensagem :: String } deriving (Generic, ToJSON)

helloHandler :: Handler Hello
helloHandler = return (Hello "ZelaAi no ar")

type API =
       Get '[JSON] Hello

  -- Users
  :<|> "users" :> "register" :> ReqBody '[JSON] D.RegisterUserDto :> Post '[JSON] D.UserResponseDto
  :<|> "users" :> "login"    :> ReqBody '[JSON] D.LoginUserDto    :> Post '[JSON] D.LoginResponseDto
  :<|> "users" :> "me" :> "occurrences"
        :> Header "Authorization" T.Text
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
  :<|> "occurrences" :> Get '[JSON] [O.OccurrenceResponseDto]

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

server :: ConnectionPool -> Server API
server pool =
       helloHandler
  :<|> Ctrl.registerController pool
  :<|> Ctrl.loginController pool
  :<|> Ctrl.listMyOccurrencesController pool
  :<|> Ctrl.listCategoriesController pool
  :<|> Ctrl.listOccurrencesByCepController pool
  :<|> (\oid auth -> Ctrl.voteController pool auth oid)
  :<|> (\oid auth -> Ctrl.unvoteController pool auth oid)
  :<|> (\oid auth dto -> Ctrl.updateStatusController pool auth oid dto)
  :<|> Ctrl.getOccurrenceController pool
  :<|> Ctrl.createOccurrenceController pool
  :<|> Ctrl.listOccurrencesController pool
  :<|> Ctrl.createPoliticianController pool
  :<|> Ctrl.mandateScoreController pool
  :<|> Ctrl.createMandateController pool
  :<|> Ctrl.listMandatesController pool

app :: ConnectionPool -> Application
app pool = serve (Proxy :: Proxy API) (server pool)
