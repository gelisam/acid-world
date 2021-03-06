
{-# LANGUAGE UndecidableInstances #-}

module Acid.Core.Backend.Memory where
import RIO
import qualified  RIO.ByteString as BS
import qualified  RIO.ByteString.Lazy as BL



import Acid.Core.State
import Acid.Core.Utils
import Acid.Core.Backend.Abstract

data AcidWorldBackendMemory





instance AcidWorldBackend AcidWorldBackendMemory where
  data AWBState AcidWorldBackendMemory = AWBStateMemory
  data AWBConfig AcidWorldBackendMemory = AWBConfigMemory deriving Show
  type AWBSerialiseT AcidWorldBackendMemory = BL.ByteString
  type AWBSerialiseConduitT AcidWorldBackendMemory = BS.ByteString
  initialiseBackend _ _  = pure . pure $ AWBStateMemory
  handleUpdateEventC _ _ awu _ ec prePersistHook postPersistHook = eBind (runUpdateC awu ec) $ \(_, r, onSuccess, onFail) -> do
    ioRPre <- onException (prePersistHook r) onFail
    onSuccess
    ioRPost <- (postPersistHook r)

    pure . Right $ (r, (ioRPre, ioRPost))

