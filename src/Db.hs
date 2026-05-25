{-# LANGUAGE OverloadedStrings #-}

module Db (withDbPool, runMigrations) where

import Control.Monad.Logger (runStdoutLoggingT)
import Control.Monad.IO.Class (liftIO)
import Database.Persist.Postgresql (withPostgresqlPool, ConnectionPool)
import Database.Persist.Sql (runSqlPool, rawSql, Single, SqlPersistT, runMigration, Migration)
import Data.Int (Int64)
import Data.ByteString.Char8 (pack)
import System.Environment (lookupEnv)
import Data.Maybe (fromMaybe)

-- | Lê a DATABASE_URL do ambiente (ou usa um default), cria o pool do Postgres,
-- roda um SELECT 1 de sanity check e entrega o pool para a ação passada.
withDbPool :: (ConnectionPool -> IO ()) -> IO ()
withDbPool action = do
  env <- lookupEnv "DATABASE_URL"
  let connStr = pack $ fromMaybe "host=localhost port=5432 user=postgres dbname=postgres password=root" env

  putStrLn $ "Using DATABASE_URL: " ++ show connStr

  runStdoutLoggingT $
    withPostgresqlPool connStr 1 $ \pool -> liftIO $ do
      putStrLn "Postgres pool created"
      _ <- runSqlPool (rawSql "SELECT 1" [] :: SqlPersistT IO [Single Int64]) pool
      putStrLn "Postgres test query succeeded"
      action pool

-- | Aplica uma 'Migration' (ex.: 'migrateAll' gerado em Repository.Entities).
runMigrations :: ConnectionPool -> Migration -> IO ()
runMigrations pool m = runStdoutLoggingT $ runSqlPool (runMigration m) pool
