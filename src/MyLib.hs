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
import qualified InterfaceAdapters.Libs as Libs
import qualified Presentation.RateLimit as RL
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
  -- Sanity check de segredos antes de qualquer coisa.
  Libs.assertJwtSecretSafe
  prod <- Libs.isProduction
  runMigrations pool migrateAll
  CC.seedDefaultCategories pool
  Seed.seedDemoIfEmpty pool
  rawOrigins <- lookupEnv "CORS_ALLOWED_ORIGINS"
  let allowed = case rawOrigins of
        Just s | not (null s) && s /= "*" -> parseOrigins s
        _ -> []
  -- Em produção, CORS aberto é vulnerabilidade: aborta o boot.
  case (prod, allowed) of
    (True, []) ->
      fail "FATAL: production requires CORS_ALLOWED_ORIGINS to be set (no wildcard)."
    (_, []) ->
      putStrLn "CORS: open (no origin restriction) — dev only."
    (_, xs) ->
      putStrLn $ "CORS: restricted to " ++ show (map BS.unpack xs)
  -- Rate limiter: aplicado em endpoints sensíveis (auth + write).
  rlMw <- RL.rateLimit
    [ RL.RateRule "/users/login"    "POST" 5  60   -- 5 / 1min (brute-force)
    , RL.RateRule "/users/register" "POST" 5  300  -- 5 / 5min (spam de conta)
    , RL.RateRule "/occurrences"    "POST" 20 60   -- criação
    , RL.RateRule "/comments"       "POST" 30 60   -- comentários
    ]
  putStrLn "RateLimit: login=5/min, register=5/5min, write endpoints throttled."
  -- Render injeta PORT; localmente o default e 5050
  rawPort <- lookupEnv "PORT"
  let port = case rawPort >>= readMaybeInt of
        Just p  -> p
        Nothing -> 5050
  putStrLn $ "server listening on :" ++ show port
  run port (rlMw (cors (buildPolicy allowed) (app pool)))

readMaybeInt :: String -> Maybe Int
readMaybeInt s = case reads s of
  [(n, "")] -> Just n
  _         -> Nothing
