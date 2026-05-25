-- | Regras de validacao para Politician e Mandate.
module Validation.MandateValidation
  ( validatePolitician
  , validateMandate
  ) where

import Dto.MandateDto
  ( CreatePoliticianDto(..)
  , CreateMandateDto(..)
  )

validatePolitician :: CreatePoliticianDto -> Either String CreatePoliticianDto
validatePolitician dto
  | null (polName dto)  = Left "name is required"
  | null (polParty dto) = Left "party is required"
  | polRole dto `notElem` ["prefeito", "governador"]
      = Left "role must be 'prefeito' or 'governador'"
  | otherwise = Right dto

validateMandate :: CreateMandateDto -> Either String CreateMandateDto
validateMandate dto
  | null (manUf dto)             = Left "uf is required"
  | length (manUf dto) /= 2      = Left "uf must have 2 chars"
  | manStartDate dto >= manEndDate dto
      = Left "startDate must be before endDate"
  | otherwise = Right dto
