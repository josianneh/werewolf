{-|
Module      : Werewolf.Commands.Start
Description : Options and handler for the start subcommand.

Copyright   : (c) Henry J. Wylde, 2016
License     : BSD3
Maintainer  : public@hjwylde.com

Options and handler for the start subcommand.
-}

{-# LANGUAGE FlexibleContexts      #-}

module Werewolf.Commands.Start (
    -- * Options
    Options(..), ExtraRoles(..),

    -- * Handle
    handle,
) where

import Control.Lens
import Control.Monad.Except
import Control.Monad.Random
import Control.Monad.Extra
import Control.Monad.State
import Control.Monad.Writer

import           Data.List
import           Data.Text (Text)
import qualified Data.Text as T

import Game.Werewolf.Engine   hiding (isGameOver)
import Game.Werewolf.Game
import Game.Werewolf.Response
import Game.Werewolf.Role

import System.Random.Shuffle

data Options = Options
    { optExtraRoles :: ExtraRoles
    , argPlayers    :: [Text]
    } deriving (Eq, Show)

data ExtraRoles = None | Random | Use [Text]
    deriving (Eq, Show)

handle :: MonadIO m => Text -> Options -> m ()
handle callerName (Options extraRoles playerNames) = do
    whenM (doesGameExist &&^ fmap (not . isGameOver) readGame) $ exitWith failure
        { messages = [gameAlreadyRunningMessage callerName]
        }

    result <- runExceptT $ do
        extraRoles' <- case extraRoles of
            None            -> return []
            Random          -> randomExtraRoles $ length playerNames
            Use roleNames   -> useExtraRoles callerName roleNames

        players <- createPlayers (callerName:playerNames) extraRoles'

        runWriterT $ startGame callerName players >>= execStateT checkStage

    case result of
        Left errorMessages      -> exitWith failure { messages = errorMessages }
        Right (game, messages)  -> writeGame game >> exitWith success { messages = messages }

randomExtraRoles :: MonadIO m => Int -> m [Role]
randomExtraRoles n = liftIO . evalRandIO $ do
    let minimum = n `div` 5 + 1

    count <- getRandomR (minimum, minimum + 2)

    take count <$> shuffleM restrictedRoles

useExtraRoles :: MonadError [Message] m => Text -> [Text] -> m [Role]
useExtraRoles callerName roleNames = forM roleNames $ \roleName -> case findByName roleName of
    Just role   -> return role
    Nothing     -> throwError [roleDoesNotExistMessage callerName roleName]

findByName :: Text -> Maybe Role
findByName name' = find ((name' ==) . T.toLower . view name) allRoles
