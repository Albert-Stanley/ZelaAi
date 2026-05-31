module Main where

  import System.IO
    ( hSetBuffering, hSetEncoding, stdout, stderr
    , BufferMode(LineBuffering), utf8
    )
  import MyLib (startApp)

  main :: IO ()
  main = do
    -- garante que logs apareçam imediatamente em ambientes containerizados
    -- (Docker/Render coleta stdout/stderr e o default BlockBuffering atrasa)
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering
    -- força UTF-8 nos handles (containers minimal vêm com locale C/POSIX
    -- que falha ao imprimir caracteres como em-dash ou acentos)
    hSetEncoding stdout utf8
    hSetEncoding stderr utf8
    startApp
