{-# LANGUAGE OverloadedStrings #-}

-- | Casos de uso de Category: listagem e seed inicial.
module UseCase.CategoryCase
  ( listCategories
  , seedDefaultCategories
  ) where

import Database.Persist (Entity(..), getBy, selectList, insert_)
import Database.Persist.Sql (ConnectionPool, runSqlPool, fromSqlKey)

import qualified Dto.CategoryDto as D
import qualified Repository.Entities as E
import qualified InterfaceAdapters.Logs as Logs

-- | Lista todas as categorias.
listCategories :: ConnectionPool -> IO [D.CategoryResponseDto]
listCategories pool = do
  rows <- runSqlPool (selectList [] []) pool
  return $ map toDto rows
  where
    toDto (Entity cid c) = D.CategoryResponseDto
      { D.categoryId   = fromSqlKey cid
      , D.categoryName = E.categoryName c
      }

-- | Insere categorias padrao se ainda nao existirem.
-- Chamado uma vez no startup do servidor.
seedDefaultCategories :: ConnectionPool -> IO ()
seedDefaultCategories pool = do
  let defaults = ["Buraco", "Iluminacao", "Esgoto", "Lixo", "Calcada"]
  mapM_ (insertIfMissing pool) defaults
  Logs.logInfo "categories seed checked"
  where
    insertIfMissing p n = do
      existing <- runSqlPool (getBy (E.UniqueCategoryName n)) p
      case existing of
        Just _  -> return ()
        Nothing -> runSqlPool (insert_ (E.Category n)) p
