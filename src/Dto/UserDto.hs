{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- | DTOs do recurso /users. Tipos puros de transporte.
module Dto.UserDto
  ( RegisterUserDto(..)
  , LoginUserDto(..)
  , UserResponseDto(..)
  , LoginResponseDto(..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Data.Int (Int64)

data RegisterUserDto = RegisterUserDto
  { name     :: String
  , username :: String
  , password :: String
  , cep      :: String
  } deriving (Generic, Show, FromJSON, ToJSON)

data LoginUserDto = LoginUserDto
  { loginUsername :: String
  , loginPassword :: String
  } deriving (Generic, Show, FromJSON, ToJSON)

data UserResponseDto = UserResponseDto
  { userId       :: Int64
  , userName     :: String
  , userUsername :: String
  , userCep      :: String
  , userCity     :: String
  , userUf       :: String
  } deriving (Generic, Show, ToJSON)

data LoginResponseDto = LoginResponseDto
  { token :: String
  , user  :: UserResponseDto
  } deriving (Generic, Show, ToJSON)
