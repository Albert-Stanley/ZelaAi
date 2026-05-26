{-# LANGUAGE OverloadedStrings #-}

-- | Middleware de rate-limit em memória.
--
-- Implementação propositalmente simples: janela deslizante de timestamps
-- por IP guardada em IORef + Data.Map. Adequado para uma instância única
-- (Render free tier, dev local). Para multi-instância em prod, trocar por
-- Redis. A estrutura é GC-amigável porque expulsamos timestamps antigos.
--
-- Aplica-se apenas a paths sensíveis (login/register/vote) para não
-- sobrecarregar leitura pública do feed.
module Presentation.RateLimit
  ( rateLimit
  , RateRule(..)
  ) where

import qualified Data.ByteString.Char8 as BS
import qualified Data.Map.Strict as Map
import Data.IORef (IORef, newIORef, atomicModifyIORef')
import Data.Time.Clock.POSIX (getPOSIXTime, POSIXTime)
import Network.HTTP.Types (Status, mkStatus)
import Network.Wai
  ( Middleware, Request, Response, responseLBS
  , rawPathInfo, requestMethod, requestHeaders, remoteHost
  )

-- | Uma regra: para qualquer request cujo path comece com `rrPath`,
-- limite a `rrMax` requisições por janela de `rrWindow` segundos por IP.
data RateRule = RateRule
  { rrPath   :: BS.ByteString   -- ^ prefixo de path (ex: "/users/login")
  , rrMethod :: BS.ByteString   -- ^ "POST", "GET", ..., ou "*" para qualquer
  , rrMax    :: Int             -- ^ máx. de requests na janela
  , rrWindow :: POSIXTime       -- ^ janela em segundos
  }

-- | Chave do bucket: ip + path (permite contadores independentes por endpoint).
type Key = BS.ByteString
type Buckets = Map.Map Key [POSIXTime]

status429 :: Status
status429 = mkStatus 429 "Too Many Requests"

-- | Cria o middleware. Construir o IORef no boot:
--   mw <- rateLimit [RateRule "/users/login" "POST" 5 60, ...]
rateLimit :: [RateRule] -> IO Middleware
rateLimit rules = do
  ref <- newIORef Map.empty
  return $ \app req respond ->
    case matchRule rules req of
      Nothing   -> app req respond
      Just rule -> do
        now <- getPOSIXTime
        let ip   = clientIp req
            key  = ip <> ":" <> rrPath rule
        allowed <- atomicModifyIORef' ref (bumpBucket key now rule)
        if allowed
          then app req respond
          else respond tooManyResponse

matchRule :: [RateRule] -> Request -> Maybe RateRule
matchRule rules req =
  let path   = rawPathInfo req
      method = requestMethod req
      ok r   = (rrPath r `BS.isPrefixOf` path)
            && (rrMethod r == "*" || rrMethod r == method)
  in firstJust [ if ok r then Just r else Nothing | r <- rules ]
  where
    firstJust = foldr (\x acc -> case x of { Just _ -> x; _ -> acc }) Nothing

bumpBucket :: Key -> POSIXTime -> RateRule -> Buckets -> (Buckets, Bool)
bumpBucket key now rule m =
  let ts  = Map.findWithDefault [] key m
      ts' = filter (\t -> now - t < rrWindow rule) ts
  in if length ts' >= rrMax rule
       then (Map.insert key ts' m, False)
       else (Map.insert key (now : ts') m, True)

tooManyResponse :: Response
tooManyResponse =
  responseLBS status429
    [("Content-Type", "application/json"), ("Retry-After", "60")]
    "{\"error\":\"too many requests, slow down\"}"

-- | Pega o IP do cliente, respeitando X-Forwarded-For (Render/nginx proxy).
clientIp :: Request -> BS.ByteString
clientIp req =
  case lookup "X-Forwarded-For" (requestHeaders req) of
    Just xff -> BS.takeWhile (/= ',') xff
    Nothing  ->
      case lookup "X-Real-IP" (requestHeaders req) of
        Just ip -> ip
        Nothing -> BS.pack (show (remoteHost req))
