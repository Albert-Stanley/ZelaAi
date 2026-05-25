{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DeriveGeneric #-}

-- | Schemas. Adicione novas entidades dentro do bloco persistLowerCase.
-- 'migrateAll' eh gerado pelo TH e cobre tudo que estiver declarado aqui.
module Repository.Entities where

import Database.Persist.TH
import Data.Time (UTCTime, Day)
import GHC.Generics (Generic)
import Data.Aeson (ToJSON)

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
User
    name       String
    username   String
    password   String
    cep        String
    city       String
    uf         String
    createdAt  UTCTime
    UniqueUsername username
    deriving Show Generic

Category
    name String
    UniqueCategoryName name
    deriving Show Generic

Politician
    name  String
    party String
    role  String
    deriving Show Generic

Mandate
    politicianId PoliticianId
    city         String
    uf           String
    startDate    Day
    endDate      Day
    deriving Show Generic

Occurrence
    userId      UserId
    categoryId  CategoryId
    mandateId   MandateId Maybe
    title       String
    description String
    photoUrl    String
    latitude    Double Maybe
    longitude   Double Maybe
    cep         String
    city        String
    uf          String
    status      String
    createdAt   UTCTime
    resolvedAt  UTCTime Maybe
    deriving Show Generic

Vote
    userId       UserId
    occurrenceId OccurrenceId
    createdAt    UTCTime
    UniqueUserOccurrence userId occurrenceId
    deriving Show Generic
|]

instance ToJSON User
instance ToJSON Category
instance ToJSON Politician
instance ToJSON Mandate
instance ToJSON Occurrence
instance ToJSON Vote
