
{-# LANGUAGE UndecidableInstances #-}

module Acid.Core.Backend.FS where
import RIO
import qualified RIO.Directory as Dir
import qualified RIO.Text as T
import qualified  RIO.ByteString.Lazy as BL


import Prelude(userError)

import Acid.Core.Segment
import Acid.Core.State
import Acid.Core.Backend.Abstract
import Conduit

newtype AcidWorldBackendFS ss nn a = AcidWorldBackendFS (IO a)
  deriving (Functor, Applicative, Monad, MonadIO, MonadThrow)





instance ( ValidSegmentNames ss
         , ValidEventNames ss nn ) =>
  AcidWorldBackend AcidWorldBackendFS ss nn where
  data AWBState AcidWorldBackendFS ss nn = AWBStateFS {
    aWBStateFSConfig :: AWBConfig AcidWorldBackendFS ss nn
  }
  data AWBConfig AcidWorldBackendFS ss nn = AWBConfigFS {
    aWBConfigFSStateDir :: FilePath
  }
  type AWBSerialiseT AcidWorldBackendFS ss nn = BL.ByteString
  initialiseBackend c _  = do
    stateP <- Dir.makeAbsolute (aWBConfigFSStateDir c)
    Dir.createDirectoryIfMissing True stateP
    let eventPath = makeEventPath stateP
    b <- Dir.doesFileExist eventPath
    when (not b) (BL.writeFile eventPath "")
    pure . pure $ AWBStateFS c{aWBConfigFSStateDir = stateP}
  loadEvents deserialiseConduit s = do
    let eventPath = makeEventPath (aWBConfigFSStateDir . aWBStateFSConfig $ s)


    pure $
         sourceFile eventPath .|
         mapC BL.fromStrict .|
         deserialiseConduit .|
         mapMC throwOnEither
    where
      throwOnEither :: (MonadThrow m) => Either Text a -> m a
      throwOnEither (Left t) = throwM $ userError (T.unpack t)
      throwOnEither (Right a) = pure a

  -- this should be bracketed and so forth @todo
  handleUpdateEvent serializer awb awu (e :: Event n) = do
    let eventPath = makeEventPath (aWBConfigFSStateDir . aWBStateFSConfig $ awb)
    stE <- mkStorableEvent e
    BL.appendFile eventPath (serializer stE)
    runUpdate awu e


makeEventPath :: FilePath -> FilePath
makeEventPath fp = fp <> "/" <> "events"