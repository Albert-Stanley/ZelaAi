{-# LANGUAGE OverloadedStrings #-}

-- | Equivalente ao logs.go. No MVP escreve no stdout. Aqui eh o ponto unico
-- de troca caso a gente queira plugar Mongo / arquivo / Sentry depois.
module InterfaceAdapters.Logs
  ( logError
  , logInfo
  ) where

import Data.Time (getCurrentTime)

logInfo :: String -> IO ()
logInfo msg = do
  ts <- getCurrentTime
  putStrLn $ "[INFO " ++ show ts ++ "] " ++ msg

logError :: String -> IO ()
logError msg = do
  ts <- getCurrentTime
  putStrLn $ "[ERR  " ++ show ts ++ "] " ++ msg
