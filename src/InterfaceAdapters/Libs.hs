{-# LANGUAGE OverloadedStrings #-}

-- | Equivalente ao libs.go: bcrypt, JWT, UUID.
module InterfaceAdapters.Libs
  ( hashPassword
  , verifyPassword
  , generateTokenJwt
  , validateTokenJwt
  , generateUuid
  , jwtSecret
  , assertJwtSecretSafe
  , isProduction
  ) where

import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T
import qualified Crypto.BCrypt as BC
import Data.Time.Clock.POSIX (getPOSIXTime)
import qualified Web.JWT as JWT
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import Data.Int (Int64)
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
import Data.Maybe (fromMaybe)

-- | Valor sentinela do default. Mantido como constante para checagem no boot.
defaultDevSecret :: String
defaultDevSecret = "zelaai_dev_secret"

-- | Le do ambiente uma unica vez (estilo helper global do Go).
jwtSecret :: String
jwtSecret = unsafePerformIO $ fmap (fromMaybe defaultDevSecret) (lookupEnv "JWT_SECRET")
{-# NOINLINE jwtSecret #-}

-- | Detecta se estamos em produção via APP_ENV / ENV / RENDER (Render seta RENDER=true).
isProduction :: IO Bool
isProduction = do
  e1 <- lookupEnv "APP_ENV"
  e2 <- lookupEnv "ENV"
  e3 <- lookupEnv "RENDER"
  let pick = fromMaybe "" (case e1 of { Just x -> Just x; _ -> e2 })
      lowered = map (\c -> if c >= 'A' && c <= 'Z' then toEnum (fromEnum c + 32) else c) pick
  return $ lowered `elem` ["production", "prod"] || e3 == Just "true"

-- | Sanidade do JWT_SECRET. Em produção, rejeita default ou segredos curtos.
-- Em dev, apenas loga aviso.
assertJwtSecretSafe :: IO ()
assertJwtSecretSafe = do
  prod <- isProduction
  let s = jwtSecret
      tooShort = length s < 32
      isDefault = s == defaultDevSecret
  case (prod, isDefault, tooShort) of
    (True,  True, _) ->
      fail "FATAL: JWT_SECRET not set in production (using default). Refusing to start."
    (True,  _,    True) ->
      fail "FATAL: JWT_SECRET is too short (< 32 chars) in production. Refusing to start."
    (False, True, _) ->
      putStrLn "WARN: using default JWT_SECRET. OK in dev, NEVER in production."
    (False, _,    True) ->
      putStrLn "WARN: JWT_SECRET is shorter than 32 chars. Increase it before production."
    _ -> return ()

-- Senhas -------------------------------------------------------------

hashPassword :: String -> IO String
hashPassword plain = do
  mhash <- BC.hashPasswordUsingPolicy BC.slowerBcryptHashingPolicy (BS.pack plain)
  case mhash of
    Nothing -> fail "bcrypt failed to hash password"
    Just bs -> return (BS.unpack bs)

verifyPassword :: String -> String -> Bool
verifyPassword plain hashed =
  BC.validatePassword (BS.pack hashed) (BS.pack plain)

-- JWT ----------------------------------------------------------------

-- | Token com subject = userId. Expira em 15min — janela curta o suficiente
-- para limitar dano de token vazado sem precisar de refresh tokens em DB.
-- O front detecta 401 e leva o usuário ao login.
generateTokenJwt :: Int64 -> IO String
generateTokenJwt uid = do
  now <- getPOSIXTime
  let expiry = now + 60 * 15         -- 15min
      cs = mempty
            { JWT.sub = JWT.stringOrURI (T.pack (show uid))
            , JWT.exp = JWT.numericDate expiry
            }
      signer = JWT.hmacSecret (T.pack jwtSecret)
      tok = JWT.encodeSigned signer mempty cs
  return (T.unpack tok)

-- | Devolve Just userId se o token eh valido e nao expirou.
validateTokenJwt :: T.Text -> Maybe Int64
validateTokenJwt token = do
  let signer = JWT.hmacSecret (T.pack jwtSecret)
  verified <- JWT.decodeAndVerifySignature (JWT.toVerify signer) token
  let cs = JWT.claims verified
  subTxt <- fmap (T.unpack . JWT.stringOrURIToText) (JWT.sub cs)
  case reads subTxt of
    [(n, "")] -> Just n
    _         -> Nothing

-- UUID ---------------------------------------------------------------

generateUuid :: IO String
generateUuid = fmap UUID.toString UUIDv4.nextRandom
