{-# LANGUAGE OverloadedStrings #-}

-- | Equivalente ao exceptionalhandler.go: wrappers de erro.
module Presentation.Errors
  ( appError
  , badRequest
  , unauthorized
  , forbidden
  , notFound
  , conflict
  , internal
  ) where

import Servant (ServerError, errBody, err400, err401, err403, err404, err409, err500)
import qualified Data.ByteString.Lazy.Char8 as BL

-- | Cria um ServerError com a mensagem como body JSON simples.
appError :: ServerError -> String -> ServerError
appError base msg = base { errBody = BL.pack ("{\"message\":\"" ++ msg ++ "\"}") }

badRequest :: String -> ServerError
badRequest = appError err400

unauthorized :: String -> ServerError
unauthorized = appError err401

forbidden :: String -> ServerError
forbidden = appError err403

notFound :: String -> ServerError
notFound = appError err404

conflict :: String -> ServerError
conflict = appError err409

internal :: String -> ServerError
internal = appError err500
