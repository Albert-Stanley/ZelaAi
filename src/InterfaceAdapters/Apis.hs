{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Equivalente ao apis.go: clientes HTTP de APIs externas. No MVP soh
-- precisamos do ViaCEP pra resolver city/uf no cadastro do usuario.
module InterfaceAdapters.Apis
  ( ViaCepResponse(..)
  , fetchCep
  ) where

import Data.Aeson (FromJSON, eitherDecode)
import GHC.Generics (Generic)
import Network.HTTP.Client (newManager, parseRequest, httpLbs, responseBody)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Control.Exception (try, SomeException)

data ViaCepResponse = ViaCepResponse
  { cep         :: Maybe String
  , logradouro  :: Maybe String
  , complemento :: Maybe String
  , bairro      :: Maybe String
  , localidade  :: Maybe String
  , uf          :: Maybe String
  , erro        :: Maybe Bool
  } deriving (Generic, Show, FromJSON)

-- | Devolve Right ViaCepResponse se o CEP eh valido,
-- Left "msg" se ViaCEP marcou como invalido ou se houve falha de rede.
fetchCep :: String -> IO (Either String ViaCepResponse)
fetchCep cepStr = do
  let url = "https://viacep.com.br/ws/" ++ cepStr ++ "/json/"
  result <- try $ do
    mgr <- newManager tlsManagerSettings
    req <- parseRequest url
    resp <- httpLbs req mgr
    return (responseBody resp)
  case result of
    Left (e :: SomeException) ->
      return $ Left ("network error: " ++ show e)
    Right body ->
      case eitherDecode body of
        Left err -> return $ Left ("decode error: " ++ err)
        Right vc ->
          if erro vc == Just True
            then return $ Left "cep not found"
            else return $ Right vc
