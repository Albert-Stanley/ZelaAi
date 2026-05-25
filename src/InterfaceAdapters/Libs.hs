{-# LANGUAGE OverloadedStrings #-}

-- | Equivalente ao libs.go: bcrypt, JWT, UUID.
module InterfaceAdapters.Libs
  ( hashPassword
  , verifyPassword
  , generateTokenJwt
  , validateTokenJwt
  , generateUuid
  , jwtSecret
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

-- | Le do ambiente uma unica vez (estilo helper global do Go).
jwtSecret :: String
jwtSecret = unsafePerformIO $ fmap (fromMaybe "zelaai_dev_secret") (lookupEnv "JWT_SECRET")
{-# NOINLINE jwtSecret #-}

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

-- | Token com subject = userId, expira em 24h.
generateTokenJwt :: Int64 -> IO String
generateTokenJwt uid = do
  now <- getPOSIXTime
  let expiry = now + 60 * 60 * 24    -- 24h
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
