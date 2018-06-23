{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_GHC -freduction-depth=0 #-}
{-# LANGUAGE TemplateHaskell #-}

module Main (main) where

import RIO
import qualified RIO.Directory as Dir

import Data.Proxy(Proxy(..))
import Acid.World
import Test.QuickCheck.Arbitrary
import Test.QuickCheck as QC
import Criterion.Main
import Criterion.Types
import TH
import qualified  RIO.ByteString.Lazy as BL
import Data.Aeson(Value(..), Object)
import Prelude (userError)
generateEventables (eventableNames 1000)


instance NFData (WrappedEvent nn ss) where
  rnf (WrappedEvent a b c) = rnf (a,b,c)
instance NFData (Event n) where
  rnf (Event _) = ()

main :: IO ()
main = do

  let conf = defaultConfig {
        timeLimit = 20
       }
  logOptions <- logOptionsHandle stderr True
  let logOptions' = setLogUseTime True logOptions

  withLogFunc logOptions' $ \lf -> do
    defaultMainWith conf [

      env (loadValues) $ \vs -> bgroup "WithValues" [
        bench "extractWrappedEvents1" (nf extractWrappedEvents1 vs),
        bench "extractWrappedEvents2" (nf extractWrappedEvents2 vs),
        bench "decodeToWrappedEvents1" (nf decodeToWrappedEvents1 vs),
        bench "decodeToWrappedEvents2" (nf decodeToWrappedEvents2 vs)

        ]

{-      bench  "fetchList" (perRunEnv (Dir.copyFile (eventPath <> ".orig") eventPath) (const $ runRIO lf fetchList)),
      bench  "fetchListWithManyEventNames" (perRunEnv (Dir.copyFile (eventPath <> ".orig") eventPath) (const $ runRIO lf fetchListWithManyEventNames)),
      bench  "fetchListWithManyEventNamesInverted" (perRunEnv (Dir.copyFile (eventPath <> ".orig") eventPath) (const $ runRIO lf fetchListWithManyEventNamesInverted))-}


      ]





instance Segment "List" where
  type SegmentS "List" = [String]
  defaultState _ = []

prependToList :: (AcidWorldUpdate m ss, HasSegment ss  "List") => String -> m ss [String]
prependToList a = do
  ls <- getSegment (Proxy :: Proxy "List")
  let newLs = a : ls
  putSegment (Proxy :: Proxy "List") newLs
  fmap (take 5) $ getSegment (Proxy :: Proxy "List")


instance Eventable "prependToList" where
  type EventArgs "prependToList" = '[String]
  type EventResult "prependToList" = [String]
  type EventSegments "prependToList" = '["List"]
  runEvent _ = toRunEvent prependToList

instance Eventable "getListState" where
  type EventArgs "getListState" = '[]
  type EventResult "getListState" = [String]
  type EventSegments "getListState" = '["List"]
  runEvent _ _ = fmap (take 10) $ getSegment (Proxy :: Proxy "List")


openMyAcidWorld :: (MonadIO m) => m (AcidWorld '["List"] '["prependToList", "getListState"])
openMyAcidWorld = openAcidWorld Nothing (Proxy :: Proxy AcidWorldBackendFS) (Proxy :: Proxy AcidWorldUpdateStatePure)

loadValues :: IO [BL.ByteString]
loadValues = do
  Dir.copyFile (eventPath <> ".orig") eventPath
  bl <- BL.readFile eventPath
  return $ filter (not . BL.null) $ BL.split 10 bl


extractWrappedEvents ::(ValidEventNames ss nn) => [(Object, Text)] -> [WrappedEvent ss nn]
extractWrappedEvents vs = do
  let ps = makeParsers
  case sequence $ map (extractWrappedEvent ps) vs of
    Left err -> error $ show err
    Right ws -> ws

extractWrappedEvents1 :: [BL.ByteString] -> [WrappedEvent '["List"] '["prependToList", "getListState"]]
extractWrappedEvents1 bs =
  case sequence . sequence $ mapM decodeToTaggedValue bs of
    Left err -> error $ show err
    Right ws -> extractWrappedEvents ws

extractWrappedEvents2 :: [BL.ByteString]  -> [WrappedEvent '["List"] (Union GeneratedEventNames '["prependToList", "getListState"]  )]
extractWrappedEvents2 bs =
  case sequence . sequence $ mapM decodeToTaggedValue bs of
    Left err -> error $ show err
    Right ws -> extractWrappedEvents ws

decodeToWrappedEvents1 :: [BL.ByteString] -> [WrappedEvent '["List"] '["prependToList", "getListState"]]
decodeToWrappedEvents1 bs =
  case decodeToWrappedEvents bs of
    Left err -> error $ show err
    Right ws -> ws

decodeToWrappedEvents2 :: [BL.ByteString] -> [WrappedEvent '["List"] (Union GeneratedEventNames '["prependToList", "getListState"]  )]
decodeToWrappedEvents2 bs =
  case decodeToWrappedEvents bs of
    Left err -> error $ show err
    Right ws -> ws


insert100k :: (HasLogFunc env) => RIO env ()
insert100k = do
  aw <- openMyAcidWorld
  ls <- liftIO $ sequence $ replicate 100000 (QC.generate arbitrary)

  mapM_ (\l -> update aw (mkEvent (Proxy :: Proxy ("prependToList")) l)) ls

  res <- update aw (mkEvent (Proxy :: Proxy ("prependToList")) "Last in")

  logInfo $ displayShow res


fetchList :: (HasLogFunc env) => RIO env [String]
fetchList = do

  aw <- openMyAcidWorld
  res <- update aw (mkEvent (Proxy :: Proxy ("getListState")))
  return res


fetchListWithManyEventNames :: (HasLogFunc env) => RIO env [String]
fetchListWithManyEventNames = do

  aw <- openMyAcidWorld2
  res <- update aw (mkEvent (Proxy :: Proxy ("getListState")))
  return res

fetchListWithManyEventNamesInverted :: (HasLogFunc env) => RIO env [String]
fetchListWithManyEventNamesInverted = do

  aw <- openMyAcidWorld3
  res <- update aw (mkEvent (Proxy :: Proxy ("getListState")))
  return res

openMyAcidWorld2 :: (MonadIO m) => m (AcidWorld '["List"] (Union GeneratedEventNames '["prependToList", "getListState"]))
openMyAcidWorld2 = openAcidWorld Nothing (Proxy :: Proxy AcidWorldBackendFS) (Proxy :: Proxy AcidWorldUpdateStatePure)


openMyAcidWorld3 :: (MonadIO m) => m (AcidWorld '["List"] (Union '["prependToList", "getListState"] GeneratedEventNames ))
openMyAcidWorld3 = openAcidWorld Nothing (Proxy :: Proxy AcidWorldBackendFS) (Proxy :: Proxy AcidWorldUpdateStatePure)