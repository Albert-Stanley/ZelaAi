{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Documentação viva da aplicação:
--
--   * 'docsHomeHandler'    — renderiza o README do projeto como HTML (/docs).
--   * 'swaggerSchemaUIServer' — Swagger UI interativa em /docs-api.
--
-- O conversor de markdown é minimalista (sem deps de parser externo) e
-- cobre o que aparece no README: headings, parágrafos, listas, code
-- fences/inline, links, blockquote, **bold** e *italic*.
--
-- O 'Swagger' do spec é gerado em 'Api.hs' (que tem acesso ao tipo da API
-- principal) e passado para 'docsServer' para evitar ciclo de imports.
module Presentation.Docs
  ( DocsAPI
  , docsServer
  , HTMLContent
  , makeSwaggerInfo
  ) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.FileEmbed (embedFile, makeRelativeToProject)
import Data.Swagger (Swagger, ToSchema)
import qualified Data.Swagger as Sw
import Control.Lens ((&), (.~), (?~))
import Servant
import Servant.Swagger.UI (SwaggerSchemaUI, swaggerSchemaUIServer)
import Network.HTTP.Media ((//), (/:))

import qualified Dto.UserDto as DU
import qualified Dto.CategoryDto as DC
import qualified Dto.OccurrenceDto as DO
import qualified Dto.VoteDto as DV
import qualified Dto.MandateDto as DM
import qualified Dto.CommentDto as DCm
import qualified UseCase.AdminCase as AC

-- ---------------------------------------------------------------- Content type

-- | Tipo HTML para o Servant — permite handlers retornarem HTML bruto.
data HTMLContent

instance Accept HTMLContent where
  contentType _ = "text" // "html" /: ("charset", "utf-8")

instance MimeRender HTMLContent LBS.ByteString where
  mimeRender _ = id

-- ---------------------------------------------------------------- README embed

-- | Embute o README.md no binário em tempo de build, ancorado na raiz
-- do projeto (onde fica o .cabal). Sem essa ancoragem, file-embed tenta
-- resolver relativo ao .hs e quebra a build.
readmeBytes :: BS.ByteString
readmeBytes = $(makeRelativeToProject "README.md" >>= embedFile)

readmeText :: T.Text
readmeText = TE.decodeUtf8 readmeBytes

-- ---------------------------------------------------------------- API & server

type DocsAPI =
       "docs" :> Get '[HTMLContent] LBS.ByteString
  :<|> SwaggerSchemaUI "docs-api" "openapi.json"

docsServer :: Swagger -> Server DocsAPI
docsServer spec = docsHomeHandler :<|> swaggerSchemaUIServer spec

-- | Aplica metadados (título, versão, descrição, licença) ao spec cru.
-- Chamado em Api.hs depois de 'toSwagger'.
makeSwaggerInfo :: Swagger -> Swagger
makeSwaggerInfo s =
  s & Sw.info . Sw.title       .~ "ZelaAi API"
    & Sw.info . Sw.version     .~ "0.1.0"
    & Sw.info . Sw.description ?~ desc
    & Sw.info . Sw.license     ?~ ("MIT" & Sw.url ?~ Sw.URL "https://opensource.org/license/mit/")
  where
    desc = "API publica do ZelaAi. Plataforma colaborativa de zeladoria publica - o 'Reclame Aqui' da infraestrutura urbana, com ranking comunitario e avaliacao das gestoes."

-- ---------------------------------------------------------------- Handlers

docsHomeHandler :: Handler LBS.ByteString
docsHomeHandler =
  return (LBS.fromStrict (TE.encodeUtf8 (wrapHtml (renderMarkdown readmeText))))

-- ---------------------------------------------------------------- HTML shell

wrapHtml :: T.Text -> T.Text
wrapHtml body = T.concat
  [ "<!DOCTYPE html><html lang=\"pt-BR\"><head>"
  , "<meta charset=\"UTF-8\"/>"
  , "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"/>"
  , "<title>ZelaAi - Documentacao</title>"
  , "<link rel=\"icon\" type=\"image/svg+xml\" href=\"/assets/favicon.svg\"/>"
  , "<style>", docsCss, "</style>"
  , "</head><body><div class=\"docs-wrap\">"
  , docsHeader
  , "<main class=\"docs-content\">", body, "</main>"
  , docsFooter
  , "</div></body></html>"
  ]

docsHeader :: T.Text
docsHeader = T.concat
  [ "<header class=\"docs-header\">"
  , "<a class=\"docs-brand\" href=\"/\"><span class=\"docs-mark\">Z</span> ZelaAi <em>docs</em></a>"
  , "<nav class=\"docs-nav\">"
  , "<a href=\"/\">App</a>"
  , "<a href=\"/docs\" class=\"active\">README</a>"
  , "<a href=\"/docs-api/\">OpenAPI</a>"
  , "<a href=\"/health\">Health</a>"
  , "</nav></header>"
  ]

docsFooter :: T.Text
docsFooter =
  "<footer class=\"docs-footer\">Pagina servida diretamente pelo backend Haskell (Servant). README embutido no binario via Template Haskell.</footer>"

docsCss :: T.Text
docsCss = T.unlines
  [ ":root{--bg:#fafaf9;--surface:#fff;--text:#1c1917;--soft:#57534e;--mute:#a8a29e;--brd:#e7e5e4;--pri:#10b981;--prid:#047857;--code:#f4f4f3;}"
  , "@media (prefers-color-scheme:dark){:root{--bg:#0a0a0a;--surface:#161616;--text:#fafaf9;--soft:#a8a29e;--mute:#78716c;--brd:#383838;--code:#222;}}"
  , "*{box-sizing:border-box;}"
  , "body{margin:0;font-family:system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--text);line-height:1.6;}"
  , ".docs-wrap{max-width:880px;margin:0 auto;padding:0 24px 80px;}"
  , ".docs-header{display:flex;justify-content:space-between;align-items:center;padding:18px 0;border-bottom:1px solid var(--brd);margin-bottom:32px;flex-wrap:wrap;gap:12px;}"
  , ".docs-brand{font-weight:800;font-size:1.2rem;color:var(--text);text-decoration:none;display:inline-flex;align-items:center;gap:8px;}"
  , ".docs-brand em{font-style:normal;color:var(--mute);font-weight:500;font-size:0.85rem;margin-left:4px;}"
  , ".docs-mark{display:inline-flex;width:28px;height:28px;background:var(--pri);color:#fff;border-radius:8px;align-items:center;justify-content:center;font-weight:800;}"
  , ".docs-nav{display:flex;gap:6px;flex-wrap:wrap;}"
  , ".docs-nav a{padding:6px 12px;border-radius:8px;color:var(--soft);text-decoration:none;font-size:0.88rem;font-weight:600;border:1px solid transparent;}"
  , ".docs-nav a:hover{background:var(--surface);border-color:var(--brd);color:var(--text);}"
  , ".docs-nav a.active{background:var(--pri);color:#fff;}"
  , ".docs-content h1{font-size:2rem;margin:32px 0 12px;font-weight:800;border-bottom:2px solid var(--brd);padding-bottom:8px;}"
  , ".docs-content h2{font-size:1.5rem;margin:28px 0 10px;font-weight:700;color:var(--prid);}"
  , ".docs-content h3{font-size:1.18rem;margin:24px 0 8px;font-weight:700;}"
  , ".docs-content h4{font-size:1rem;margin:18px 0 6px;font-weight:700;color:var(--soft);}"
  , ".docs-content p{margin:0 0 14px;}"
  , ".docs-content a{color:var(--pri);text-decoration:none;border-bottom:1px dashed var(--pri);}"
  , ".docs-content a:hover{color:var(--prid);border-style:solid;}"
  , ".docs-content ul,.docs-content ol{margin:0 0 16px;padding-left:26px;}"
  , ".docs-content li{margin-bottom:4px;}"
  , ".docs-content code{background:var(--code);padding:2px 6px;border-radius:5px;font-size:0.88em;font-family:ui-monospace,SFMono-Regular,monospace;}"
  , ".docs-content pre{background:var(--code);padding:14px 16px;border-radius:8px;overflow-x:auto;border:1px solid var(--brd);margin:0 0 16px;}"
  , ".docs-content pre code{background:transparent;padding:0;border-radius:0;font-size:0.85em;}"
  , ".docs-content blockquote{margin:0 0 16px;padding:10px 16px;border-left:4px solid var(--pri);background:var(--surface);color:var(--soft);border-radius:0 6px 6px 0;}"
  , ".docs-content strong{font-weight:700;}"
  , ".docs-content em{font-style:italic;}"
  , ".docs-content hr{border:0;border-top:1px solid var(--brd);margin:32px 0;}"
  , ".docs-content table{border-collapse:collapse;margin:0 0 16px;width:100%;display:block;overflow-x:auto;}"
  , ".docs-content th,.docs-content td{border:1px solid var(--brd);padding:8px 12px;text-align:left;}"
  , ".docs-content th{background:var(--code);font-weight:700;}"
  , ".docs-content img{max-width:100%;border-radius:8px;}"
  , ".docs-footer{margin-top:48px;padding-top:18px;border-top:1px solid var(--brd);font-size:0.84rem;color:var(--mute);text-align:center;}"
  ]

-- ---------------------------------------------------------------- Markdown -> HTML

-- | Conversor minimalista feito a mão (sem dependência externa de parser).
-- Suficiente para o README/DOCS do projeto.
renderMarkdown :: T.Text -> T.Text
renderMarkdown = T.intercalate "\n" . renderBlocks . T.lines

-- | Estado do parser linha-a-linha.
data PState = PState
  { psOut    :: [T.Text]      -- linhas de saída prontas (invertidas)
  , psPara   :: [T.Text]      -- texto do parágrafo em construção
  , psList   :: Maybe Char    -- 'u' (ul), 'o' (ol), Nothing (fora)
  , psCode   :: Maybe T.Text  -- Just lang dentro de ``` ... ```
  , psBlockq :: [T.Text]      -- linhas dentro de blockquote
  }

empty0 :: PState
empty0 = PState [] [] Nothing Nothing []

renderBlocks :: [T.Text] -> [T.Text]
renderBlocks ls = reverse (psOut (flushAll (foldl step empty0 ls)))

flushAll :: PState -> PState
flushAll = flushPara . flushList . flushBlockq

flushList :: PState -> PState
flushList s = case psList s of
  Just 'u' -> s { psList = Nothing, psOut = "</ul>" : psOut s }
  Just 'o' -> s { psList = Nothing, psOut = "</ol>" : psOut s }
  _        -> s

flushBlockq :: PState -> PState
flushBlockq s
  | null (psBlockq s) = s
  | otherwise =
      let inner = T.intercalate "<br/>" (reverse (psBlockq s))
      in  s { psBlockq = [], psOut = T.concat ["<blockquote>", inner, "</blockquote>"] : psOut s }

flushPara :: PState -> PState
flushPara s
  | null (psPara s) = s
  | otherwise =
      let txt = T.intercalate " " (reverse (psPara s))
      in  s { psPara = [], psOut = T.concat ["<p>", inline txt, "</p>"] : psOut s }

step :: PState -> T.Text -> PState
step st raw
  -- dentro de code fence: ` ``` ` fecha; resto vai literal
  | Just _ <- psCode st
  , T.isPrefixOf "```" raw =
      st { psCode = Nothing
         , psOut  = "</code></pre>" : psOut st
         }
  | Just _ <- psCode st =
      st { psOut = escapeHtmlT raw : psOut st }

  -- abre code fence
  | T.isPrefixOf "```" raw =
      let lang = T.strip (T.drop 3 raw)
          st'  = flushAll st
      in  st' { psCode = Just lang
              , psOut  = T.concat ["<pre><code class=\"lang-", lang, "\">"] : psOut st'
              }

  -- horizontal rule
  | T.strip raw `elem` ["---", "***", "___"] =
      let st' = flushAll st in st' { psOut = "<hr/>" : psOut st' }

  -- heading (# ## ###...)
  | Just (n, rest) <- matchHeading raw =
      let st' = flushAll st
          tag = T.pack ("h" ++ show n)
      in  st' { psOut = T.concat ["<", tag, ">", inline rest, "</", tag, ">"] : psOut st' }

  -- blockquote
  | T.isPrefixOf "> " raw =
      let st' = flushPara (flushList st)
      in  st' { psBlockq = inline (T.drop 2 raw) : psBlockq st' }

  -- unordered list
  | T.isPrefixOf "- " raw || T.isPrefixOf "* " raw =
      let item = inline (T.drop 2 raw)
          st0  = flushPara (flushBlockq st)
          st1  = case psList st0 of
                   Just 'u' -> st0
                   _        -> let s = flushList st0 in s { psList = Just 'u', psOut = "<ul>" : psOut s }
      in  st1 { psOut = T.concat ["<li>", item, "</li>"] : psOut st1 }

  -- ordered list "1. "
  | Just rest <- matchOrdered raw =
      let item = inline rest
          st0  = flushPara (flushBlockq st)
          st1  = case psList st0 of
                   Just 'o' -> st0
                   _        -> let s = flushList st0 in s { psList = Just 'o', psOut = "<ol>" : psOut s }
      in  st1 { psOut = T.concat ["<li>", item, "</li>"] : psOut st1 }

  -- linha em branco: flush tudo
  | T.null (T.strip raw) =
      flushAll st

  -- parágrafo normal
  | otherwise =
      let st' = flushList (flushBlockq st)
      in  st' { psPara = raw : psPara st' }

matchHeading :: T.Text -> Maybe (Int, T.Text)
matchHeading raw =
  case T.span (== '#') raw of
    (hs, rest)
      | n >= 1, n <= 6, Just rest' <- T.stripPrefix " " rest -> Just (n, rest')
      where n = T.length hs
    _ -> Nothing

matchOrdered :: T.Text -> Maybe T.Text
matchOrdered raw =
  case T.span (`elem` ("0123456789" :: String)) raw of
    (ds, rest)
      | not (T.null ds), Just rest' <- T.stripPrefix ". " rest -> Just rest'
    _ -> Nothing

-- ---------------------------------------------------------------- Inline rules

-- Ordem importa: escape -> code (`x`) -> bold/italic -> links/imgs.
inline :: T.Text -> T.Text
inline = applyLinks . applyImgs . applyItalic . applyBold . applyCode . escapeHtmlT

applyCode :: T.Text -> T.Text
applyCode t =
  let parts = T.splitOn "`" t
  in T.concat (zipWith wrap [0::Int ..] parts)
  where
    wrap i seg
      | even i    = seg
      | otherwise = T.concat ["<code>", seg, "</code>"]

applyBold :: T.Text -> T.Text
applyBold = pairWrap "**" "<strong>" "</strong>"

applyItalic :: T.Text -> T.Text
applyItalic = pairWrap "*" "<em>" "</em>"

applyImgs :: T.Text -> T.Text
applyImgs t =
  case T.splitOn "![" t of
    []     -> ""
    (h:rs) -> T.concat (h : map closeImg rs)
  where
    closeImg seg =
      let (alt, rest) = T.breakOn "](" seg
      in  case T.stripPrefix "](" rest of
            Just url' ->
              let (url, after) = T.breakOn ")" url'
              in  T.concat ["<img src=\"", url, "\" alt=\"", alt, "\"/>", T.drop 1 after]
            Nothing -> T.concat ["![", seg]

applyLinks :: T.Text -> T.Text
applyLinks t =
  case T.splitOn "[" t of
    []     -> ""
    (h:rs) -> T.concat (h : map closeLink rs)
  where
    closeLink seg =
      let (txt, rest) = T.breakOn "](" seg
      in  case T.stripPrefix "](" rest of
            Just url' ->
              let (url, after) = T.breakOn ")" url'
              in  T.concat ["<a href=\"", url, "\">", txt, "</a>", T.drop 1 after]
            Nothing -> T.concat ["[", seg]

pairWrap :: T.Text -> T.Text -> T.Text -> T.Text -> T.Text
pairWrap marker openT closeT t =
  let parts = T.splitOn marker t
  in T.concat (zipWith
                 (\i p -> if even i then p else T.concat [openT, p, closeT])
                 [0::Int ..]
                 parts)

escapeHtmlT :: T.Text -> T.Text
escapeHtmlT =
    T.replace "<" "&lt;"
  . T.replace ">" "&gt;"
  . T.replace "&" "&amp;"

-- ---------------------------------------------------------------- ToSchema instances
-- Necessário para servant-swagger gerar o spec automático a partir dos tipos.

instance ToSchema DU.RegisterUserDto
instance ToSchema DU.LoginUserDto
instance ToSchema DU.UserResponseDto
instance ToSchema DU.LoginResponseDto
instance ToSchema DU.SetRoleDto
instance ToSchema DC.CategoryResponseDto
instance ToSchema DO.CreateOccurrenceDto
instance ToSchema DO.UpdateOccurrenceDto
instance ToSchema DO.UpdateStatusDto
instance ToSchema DO.OccurrenceResponseDto
instance ToSchema DO.NearbyOccurrenceDto
instance ToSchema DV.VoteResponseDto
instance ToSchema DM.CreatePoliticianDto
instance ToSchema DM.PoliticianResponseDto
instance ToSchema DM.CreateMandateDto
instance ToSchema DM.MandateResponseDto
instance ToSchema DM.ScoreResponseDto
instance ToSchema DCm.CreateCommentDto
instance ToSchema DCm.CommentResponseDto
instance ToSchema DCm.UpdateCommentDto
instance ToSchema AC.AdminStatsDto
