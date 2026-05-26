{-# LANGUAGE OverloadedStrings #-}

-- | Casos de uso de Comment: criar, listar por ocorrência, deletar,
-- listar do user logado.
module UseCase.CommentCase
  ( createComment
  , editComment
  , listCommentsByOccurrence
  , deleteComment
  , listMyComments
  ) where

import Data.Time (getCurrentTime)
import Data.List (sortOn)
import Database.Persist
  ( Entity(..), get, selectList, insert, delete, update, (==.), (=.)
  )
import Database.Persist.Sql (ConnectionPool, runSqlPool, fromSqlKey, toSqlKey)

import qualified Dto.CommentDto as D
import qualified Repository.Entities as E
import qualified InterfaceAdapters.Logs as Logs

-- | Cria um comentário em uma ocorrência. Body não pode ser vazio.
createComment
  :: ConnectionPool
  -> E.UserId
  -> Int           -- ^ occurrence id
  -> String        -- ^ body do comentário
  -> IO (Either String D.CommentResponseDto)
createComment pool uid oidInt body = do
  let trimmed = trim body
  if null trimmed
    then return $ Left "comment body is empty"
    else if length trimmed > 1000
      then return $ Left "comment too long (max 1000 chars)"
      else do
        let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
        mo <- runSqlPool (get oid) pool
        case mo of
          Nothing -> return $ Left "occurrence not found"
          Just o
            | E.occurrenceDeletedAt o /= Nothing -> return $ Left "occurrence not found"
            | otherwise -> do
                now <- getCurrentTime
                let c = E.Comment
                          { E.commentOccurrenceId = oid
                          , E.commentUserId       = uid
                          , E.commentBody         = trimmed
                          , E.commentCreatedAt    = now
                          }
                cid <- runSqlPool (insert c) pool
                Logs.logInfo $ "comment created: " ++ show (fromSqlKey cid) ++ " on occ " ++ show oidInt
                username <- userOf pool uid
                return $ Right D.CommentResponseDto
                  { D.commentId           = fromSqlKey cid
                  , D.commentOccurrenceId = fromSqlKey oid
                  , D.commentUserId       = fromSqlKey uid
                  , D.commentUsername     = username
                  , D.commentBody         = trimmed
                  , D.commentCreatedAt    = now
                  }

-- | Edita o body de um comentário. Apenas o autor pode.
editComment
  :: ConnectionPool
  -> E.UserId
  -> Int           -- ^ comment id
  -> String        -- ^ novo body
  -> IO (Either String D.CommentResponseDto)
editComment pool reqUid cidInt body = do
  let trimmed = trim body
  if null trimmed
    then return $ Left "comment body is empty"
    else if length trimmed > 1000
      then return $ Left "comment too long (max 1000 chars)"
      else do
        let cid = toSqlKey (fromIntegral cidInt) :: E.CommentId
        mc <- runSqlPool (get cid) pool
        case mc of
          Nothing -> return $ Left "comment not found"
          Just c
            | E.commentUserId c /= reqUid -> return $ Left "forbidden"
            | otherwise -> do
                runSqlPool (update cid [E.CommentBody =. trimmed]) pool
                username <- userOf pool reqUid
                return $ Right D.CommentResponseDto
                  { D.commentId           = fromSqlKey cid
                  , D.commentOccurrenceId = fromSqlKey (E.commentOccurrenceId c)
                  , D.commentUserId       = fromSqlKey reqUid
                  , D.commentUsername     = username
                  , D.commentBody         = trimmed
                  , D.commentCreatedAt    = E.commentCreatedAt c
                  }

-- | Lista comentários da ocorrência, ordenados por createdAt asc (cronológico).
listCommentsByOccurrence :: ConnectionPool -> Int -> IO [D.CommentResponseDto]
listCommentsByOccurrence pool oidInt = do
  let oid = toSqlKey (fromIntegral oidInt) :: E.OccurrenceId
  cs <- runSqlPool (selectList [E.CommentOccurrenceId ==. oid] []) pool
  mapM (toDto pool) (sortOn (\(Entity _ c) -> E.commentCreatedAt c) cs)

-- | Deleta um comentário. Autor ou admin podem.
deleteComment
  :: ConnectionPool
  -> E.UserId
  -> Bool          -- ^ isAdmin?
  -> Int           -- ^ comment id
  -> IO (Either String ())
deleteComment pool reqUid isAdmin cidInt = do
  let cid = toSqlKey (fromIntegral cidInt) :: E.CommentId
  mc <- runSqlPool (get cid) pool
  case mc of
    Nothing -> return $ Left "comment not found"
    Just c
      | not isAdmin && E.commentUserId c /= reqUid -> return $ Left "forbidden"
      | otherwise -> do
          runSqlPool (delete cid) pool
          Logs.logInfo $ "comment " ++ show cidInt ++ " deleted by user " ++ show (fromSqlKey reqUid)
          return $ Right ()

-- | Lista comentários do user logado, ordenados por mais recentes primeiro.
listMyComments :: ConnectionPool -> E.UserId -> IO [D.CommentResponseDto]
listMyComments pool uid = do
  cs <- runSqlPool (selectList [E.CommentUserId ==. uid] []) pool
  withDtos <- mapM (toDto pool) cs
  return $ reverse $ sortOn D.commentCreatedAt withDtos

-- Helpers ------------------------------------------------------------

toDto :: ConnectionPool -> Entity E.Comment -> IO D.CommentResponseDto
toDto pool (Entity cid c) = do
  username <- userOf pool (E.commentUserId c)
  return D.CommentResponseDto
    { D.commentId           = fromSqlKey cid
    , D.commentOccurrenceId = fromSqlKey (E.commentOccurrenceId c)
    , D.commentUserId       = fromSqlKey (E.commentUserId c)
    , D.commentUsername     = username
    , D.commentBody         = E.commentBody c
    , D.commentCreatedAt    = E.commentCreatedAt c
    }

userOf :: ConnectionPool -> E.UserId -> IO String
userOf pool uid = do
  mu <- runSqlPool (get uid) pool
  return $ maybe "?" E.userUsername mu

trim :: String -> String
trim = f . f where f = dropWhile (== ' ') . reverse
