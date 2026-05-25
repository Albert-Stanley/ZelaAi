{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

-- | CRUD genérico no estilo Spring Data / GORM. Cada função recebe o pool
-- e a(s) entidade(s)/chave(s) e delega para os primitivos do Persistent.
module Repository.Generic
  ( save
  , findById
  , findAll
  , updateOne
  , deleteOne
  ) where

import Database.Persist
import Database.Persist.Sql (SqlBackend, ConnectionPool, runSqlPool)

save :: (PersistRecordBackend e SqlBackend, SafeToInsert e)
     => ConnectionPool -> e -> IO (Key e)
save pool e = runSqlPool (insert e) pool

findById :: PersistRecordBackend e SqlBackend
         => ConnectionPool -> Key e -> IO (Maybe e)
findById pool k = runSqlPool (get k) pool

findAll :: PersistRecordBackend e SqlBackend
        => ConnectionPool -> IO [Entity e]
findAll pool = runSqlPool (selectList [] []) pool

updateOne :: PersistRecordBackend e SqlBackend
          => ConnectionPool -> Key e -> e -> IO ()
updateOne pool k e = runSqlPool (replace k e) pool

deleteOne :: forall e. PersistRecordBackend e SqlBackend
          => ConnectionPool -> Key e -> IO ()
deleteOne pool k = runSqlPool (delete k) pool
