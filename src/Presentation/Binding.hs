-- | Equivalente ao binding.go: helpers JSON. No Servant a desserializacao
-- ja eh feita pelo combinador ReqBody, entao aqui ficam helpers leves.
module Presentation.Binding
  ( liftEither
  ) where

import Servant (Handler, ServerError, throwError)

-- | Converte um Either ServerError a em Handler a.
liftEither :: Either ServerError a -> Handler a
liftEither (Left e)  = throwError e
liftEither (Right v) = return v
