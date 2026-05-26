-- | Regras de validacao para Occurrence.
module Validation.OccurrenceValidation
  ( validateCreate
  ) where

import Dto.OccurrenceDto (CreateOccurrenceDto(..))
import Data.Char (isDigit, toLower)
import Data.List (isPrefixOf)

maxTitle, minTitle, maxDescription, minDescription, maxPhotoUrl :: Int
minTitle       = 5
maxTitle       = 150
minDescription = 10
maxDescription = 2000
maxPhotoUrl    = 2048

-- | Apenas http(s). Bloqueia javascript:, data:, file:, etc. (anti-XSS).
isSafePhotoUrl :: String -> Bool
isSafePhotoUrl raw =
  let s = map toLower raw
  in (("http://" `isPrefixOf` s) || ("https://" `isPrefixOf` s))
     && length raw <= maxPhotoUrl
     && not (any (`elem` ("\r\n\t\0" :: String)) raw)

validateCreate :: CreateOccurrenceDto -> Either String CreateOccurrenceDto
validateCreate dto
  | null (title dto)                       = Left "title is required"
  | length (title dto) < minTitle          = Left $ "title must be at least " ++ show minTitle ++ " chars"
  | length (title dto) > maxTitle          = Left $ "title must be at most " ++ show maxTitle ++ " chars"
  | null (description dto)                 = Left "description is required"
  | length (description dto) < minDescription
      = Left $ "description must be at least " ++ show minDescription ++ " chars"
  | length (description dto) > maxDescription
      = Left $ "description must be at most " ++ show maxDescription ++ " chars"
  | null (photoUrl dto)                    = Left "photoUrl is required"
  | not (isSafePhotoUrl (photoUrl dto))    = Left "photoUrl must be a valid http(s) URL"
  | not (validCepIfPresent (cep dto))      = Left "cep must have 8 digits"
  | otherwise                              = Right dto
  where
    validCepIfPresent Nothing  = True
    validCepIfPresent (Just c) = length c == 8 && all isDigit c
