{-# LANGUAGE OverloadedStrings #-}

-- | Equivalente ao auth.go: extrai e valida JWT do header Authorization,
-- retornando o user id que ficou guardado no claim 'sub'.
module Presentation.Auth
  ( extractUserId
  ) where

import qualified Data.Text as T
import Servant (Handler, throwError)
import Database.Persist.Sql (toSqlKey)
import Repository.Entities (UserId)
import qualified InterfaceAdapters.Libs as Libs
import qualified Presentation.Errors as Err

-- | Recebe o conteudo cru do header Authorization (pode vir como Maybe Text
-- de um combinador Servant Header) e devolve o UserId valido.
extractUserId :: Maybe T.Text -> Handler UserId
extractUserId Nothing = throwError $ Err.unauthorized "missing Authorization header"
extractUserId (Just raw) = do
  let token = stripBearer raw
  case Libs.validateTokenJwt token of
    Nothing -> throwError $ Err.unauthorized "invalid or expired token"
    Just uid -> return (toSqlKey uid)

stripBearer :: T.Text -> T.Text
stripBearer t =
  let lower = T.toLower (T.take 7 t)
  in if lower == "bearer " then T.drop 7 t else t
