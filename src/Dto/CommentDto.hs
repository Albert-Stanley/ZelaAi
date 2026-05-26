{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- | DTOs do recurso /comments.
module Dto.CommentDto
  ( CreateCommentDto(..)
  , CommentResponseDto(..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Data.Int (Int64)
import Data.Time (UTCTime)

data CreateCommentDto = CreateCommentDto
  { newCommentBody :: String
  } deriving (Generic, Show, FromJSON, ToJSON)

data CommentResponseDto = CommentResponseDto
  { commentId           :: Int64
  , commentOccurrenceId :: Int64
  , commentUserId       :: Int64
  , commentUsername     :: String
  , commentBody         :: String
  , commentCreatedAt    :: UTCTime
  } deriving (Generic, Show, ToJSON)
