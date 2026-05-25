-- | Regras de validacao dos DTOs de User.
module Validation.UserValidation
  ( validateRegister
  , validateLogin
  ) where

import Dto.UserDto (RegisterUserDto(..), LoginUserDto(..))
import Data.Char (isDigit)

maxName, maxUsername, maxPassword, cepLen :: Int
maxName     = 100
maxUsername = 30
maxPassword = 20
cepLen      = 8

validateRegister :: RegisterUserDto -> Either String RegisterUserDto
validateRegister dto
  | null (name dto)                       = Left "name is required"
  | length (name dto) > maxName           = Left $ "name must be at most " ++ show maxName ++ " chars"
  | null (username dto)                   = Left "username is required"
  | length (username dto) > maxUsername   = Left $ "username must be at most " ++ show maxUsername ++ " chars"
  | null (password dto)                   = Left "password is required"
  | length (password dto) > maxPassword   = Left $ "password must be at most " ++ show maxPassword ++ " chars"
  | null (cep dto)                        = Left "cep is required"
  | length (cep dto) /= cepLen            = Left $ "cep must have exactly " ++ show cepLen ++ " digits"
  | not (all isDigit (cep dto))           = Left "cep must contain only digits"
  | otherwise                             = Right dto

validateLogin :: LoginUserDto -> Either String LoginUserDto
validateLogin dto
  | null (loginUsername dto) = Left "username is required"
  | null (loginPassword dto) = Left "password is required"
  | otherwise                = Right dto
