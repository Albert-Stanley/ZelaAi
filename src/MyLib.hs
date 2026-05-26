{-# LANGUAGE OverloadedStrings #-}

-- | Bootstrap do servidor. Conecta DB, roda migrations, faz seed,
-- aplica CORS e sobe Warp.
module MyLib (startApp) where

import qualified Data.ByteString.Char8 as BS
import Data.List (find)
import System.Environment (lookupEnv)
import Network.Wai (Request, requestHeaders)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.Cors
  ( cors, CorsResourcePolicy(..) )

import Db (withDbPool, runMigrations)
import Repository.Entities (migrateAll)
import qualified UseCase.CategoryCase as CC
import qualified UseCase.SeedCase as Seed
import Api (app)

-- | Lista de origins permitidas, lida da env var CORS_ALLOWED_ORIGINS.
-- Formato: "https://app.com,https://outro.com"
-- Se vazia ou contiver "*", permite qualquer origem (modo dev).
parseOrigins :: String -> [BS.ByteString]
parseOrigins = map (BS.pack . trim) . splitOn ','
  where
    splitOn c = foldr step [[]]
      where step ch acc@(cur:rest) | ch == c = []:acc | otherwise = (ch:cur):rest
            step _  []                       = [[]]
    trim = dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse

-- | Constrói a política dinamicamente baseado na origin da request.
-- - Sem whitelist  -> permite qualquer origem (modo dev).
-- - Com whitelist  -> ecoa apenas origens permitidas + Vary: Origin.
--   Requests sem header Origin (ex: curl) passam.
--   Requests com Origin NÃO permitida retornam Nothing (middleware nega).
buildPolicy :: [BS.ByteString] -> Request -> Maybe CorsResourcePolicy
buildPolicy allowed req
  | null allowed = Just (basePolicy { corsOrigins = Nothing })
  | otherwise =
      case lookup "Origin" (requestHeaders req) of
        Just o
          | o `elem` allowed ->
              Just $ basePolicy
                { corsOrigins    = Just ([o], True)
                , corsVaryOrigin = True
                }
          | otherwise -> Nothing   -- origin não autorizada -> bloqueia
        Nothing -> Just (basePolicy { corsOrigins = Nothing })  -- sem origin: curl/health
  where
    basePolicy = CorsResourcePolicy
      { corsOrigins        = Nothing
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
  Seed.seedDemoIfEmpty pool
  rawOrigins <- lookupEnv "CORS_ALLOWED_ORIGINS"
  let allowed = case rawOrigins of
        Just s | not (null s) && s /= "*" -> parseOrigins s
        _ -> []
  case allowed of
    [] -> putStrLn "CORS: open (no origin restriction)"
    xs -> putStrLn $ "CORS: restricted to " ++ show (map BS.unpack xs)
  -- Render injeta PORT; localmente o default e 5050
  rawPort <- lookupEnv "PORT"
  let port = case rawPort >>= readMaybeInt of
        Just p  -> p
        Nothing -> 5050
  putStrLn $ "server listening on :" ++ show port
  run port (cors (buildPolicy allowed) (app pool))

readMaybeInt :: String -> Maybe Int
readMaybeInt s = case reads s of
  [(n, "")] -> Just n
  _         -> Nothing
