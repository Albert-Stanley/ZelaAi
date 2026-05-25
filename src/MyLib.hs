{-# LANGUAGE OverloadedStrings #-}

-- | Bootstrap do servidor. Conecta DB, roda migrations, faz seed,
-- aplica CORS e sobe Warp.
module MyLib (startApp) where

import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.Cors
  ( cors, CorsResourcePolicy(..) )

import Db (withDbPool, runMigrations)
import Repository.Entities (migrateAll)
import qualified UseCase.CategoryCase as CC
import Api (app)

-- | Permite qualquer origem (MVP). Em prod restringir corsOrigins.
corsPolicy :: CorsResourcePolicy
corsPolicy = CorsResourcePolicy
  { corsOrigins        = Nothing                       -- = "*"
  , corsMethods        = ["GET","POST","DELETE","OPTIONS","PUT","PATCH"]
  , corsRequestHeaders = ["Content-Type","Authorization"]
  , corsExposedHeaders = Nothing
  , corsMaxAge         = Just 3600
  , corsVaryOrigin     = False
  , corsRequireOrigin  = False
  , corsIgnoreFailures = False
  }

startApp :: IO ()
startApp = withDbPool $ \pool -> do
  runMigrations pool migrateAll
  CC.seedDefaultCategories pool
  putStrLn "servidor em http://localhost:5050"
  run 5050 (cors (const (Just corsPolicy)) (app pool))
