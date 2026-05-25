-- | Regras de validacao para Occurrence.
module Validation.OccurrenceValidation
  ( validateCreate
  ) where

import Dto.OccurrenceDto (CreateOccurrenceDto(..))
import Data.Char (isDigit)

maxTitle, maxDescription :: Int
maxTitle       = 150
maxDescription = 2000

validateCreate :: CreateOccurrenceDto -> Either String CreateOccurrenceDto
validateCreate dto
  | null (title dto)                       = Left "title is required"
  | length (title dto) > maxTitle          = Left $ "title must be at most " ++ show maxTitle ++ " chars"
  | null (description dto)                 = Left "description is required"
  | length (description dto) > maxDescription
      = Left $ "description must be at most " ++ show maxDescription ++ " chars"
  | null (photoUrl dto)                    = Left "photoUrl is required"
  | not (validCepIfPresent (cep dto))      = Left "cep must have 8 digits"
  | otherwise                              = Right dto
  where
    validCepIfPresent Nothing  = True
    validCepIfPresent (Just c) = length c == 8 && all isDigit c
