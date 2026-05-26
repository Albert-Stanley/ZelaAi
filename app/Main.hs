module Main where

  import System.IO (hSetBuffering, stdout, stderr, BufferMode(LineBuffering))
  import MyLib (startApp)

  main :: IO ()
  main = do
    -- garante que logs apareçam imediatamente em ambientes containerizados
    -- (Docker/Render coleta stdout/stderr e o default BlockBuffering atrasa)
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering
    startApp
