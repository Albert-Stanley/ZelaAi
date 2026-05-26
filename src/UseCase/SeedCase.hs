{-# LANGUAGE OverloadedStrings #-}

-- | Seed automatico de dados de demo.
-- Roda no startup APENAS se a tabela occurrence estiver vazia.
-- Idempotente: re-rodar nao duplica nada.
-- Pode ser desligado com SEED_DEMO=false.
module UseCase.SeedCase (seedDemoIfEmpty) where

import Control.Monad (forM_)
import Data.Time (UTCTime, getCurrentTime, addUTCTime, fromGregorian)
import Database.Persist (Entity(..), Filter, count, getBy, insert, insert_, selectList)
import Database.Persist.Sql (ConnectionPool, runSqlPool)
import System.Environment (lookupEnv)

import qualified Repository.Entities as E
import qualified InterfaceAdapters.Libs as Libs
import qualified InterfaceAdapters.Logs as Logs

-- | Verifica a flag SEED_DEMO. Default = true.
seedEnabled :: IO Bool
seedEnabled = do
  v <- lookupEnv "SEED_DEMO"
  return $ case v of
    Just s  -> not (s `elem` ["false", "0", "no", "off"])
    Nothing -> True

-- | Verifica se ha ocorrencias; se nao, popula dados de demo.
seedDemoIfEmpty :: ConnectionPool -> IO ()
seedDemoIfEmpty pool = do
  enabled <- seedEnabled
  if not enabled then Logs.logInfo "seed-demo: disabled by SEED_DEMO env" else do
    n <- runSqlPool (count ([] :: [Filter E.Occurrence])) pool
    if n > 0
      then Logs.logInfo $ "seed-demo: skipped (" ++ show n ++ " occurrences already exist)"
      else do
        Logs.logInfo "seed-demo: empty DB, populating demo data..."
        now <- getCurrentTime
        runSeed pool now
        Logs.logInfo "seed-demo: done"

-- ---------------------------------------------------------------------------
-- Conteudo do seed
-- ---------------------------------------------------------------------------

runSeed :: ConnectionPool -> UTCTime -> IO ()
runSeed pool now = do
  -- 1) usuario demo
  hashed <- Libs.hashPassword "demo1234"
  let demoUser = E.User
        { E.userName      = "Cidadao Demo"
        , E.userUsername  = "demo"
        , E.userPassword  = hashed
        , E.userCep       = "01310100"
        , E.userCity      = "Sao Paulo"
        , E.userUf        = "SP"
        , E.userCreatedAt = now
        }
  uid <- ensureUser pool demoUser
  Logs.logInfo "  + user @demo (senha: demo1234)"

  -- usuarios extras pra dar volume nos votos
  uids <- mapM (\(n, un, cep, c, u) -> do
    h <- Libs.hashPassword "demo1234"
    ensureUser pool E.User
      { E.userName = n, E.userUsername = un, E.userPassword = h
      , E.userCep = cep, E.userCity = c, E.userUf = u, E.userCreatedAt = now }
    ) extraUsers
  Logs.logInfo $ "  + " ++ show (length uids) ++ " usuarios extras"

  -- 2) politicos + mandatos (3 cidades)
  prefSpId <- runSqlPool (insert (E.Politician "Ana Souza"      "PCD" "prefeito"))   pool
  prefRjId <- runSqlPool (insert (E.Politician "Carlos Andrade" "PRJ" "prefeito"))   pool
  prefBhId <- runSqlPool (insert (E.Politician "Beatriz Lima"   "PMG" "prefeita"))   pool
  govSpId  <- runSqlPool (insert (E.Politician "Joao Oliveira"  "PVD" "governador")) pool

  let mkMandate polId city uf = E.Mandate polId city uf (fromGregorian 2025 1 1) (fromGregorian 2028 12 31)
  manSp <- runSqlPool (insert (mkMandate prefSpId "Sao Paulo"      "SP")) pool
  manRj <- runSqlPool (insert (mkMandate prefRjId "Rio de Janeiro" "RJ")) pool
  manBh <- runSqlPool (insert (mkMandate prefBhId "Belo Horizonte" "MG")) pool
  _     <- runSqlPool (insert (E.Mandate govSpId "" "SP" (fromGregorian 2023 1 1) (fromGregorian 2026 12 31))) pool
  Logs.logInfo "  + 4 politicos / 4 mandatos"

  -- 3) ids de categorias (ja existem por seedDefaultCategories)
  cats <- runSqlPool (selectList ([] :: [Filter E.Category]) []) pool
  let catId name = case filter (\(Entity _ c) -> E.categoryName c == name) cats of
        (Entity cid _:_) -> Just cid
        _                -> Nothing
      buraco = fromMaybeKey (catId "Buraco")
      luz    = fromMaybeKey (catId "Iluminacao")
      esgoto = fromMaybeKey (catId "Esgoto")
      lixo   = fromMaybeKey (catId "Lixo")
      cal    = fromMaybeKey (catId "Calcada")

  -- 4) ocorrencias com fotos do Unsplash + lat/lng reais + datas variadas
  let mkOcc owner cat mand title desc photo lat lng cep city uf status daysAgo resolved =
        E.Occurrence
          { E.occurrenceUserId      = owner
          , E.occurrenceCategoryId  = cat
          , E.occurrenceMandateId   = Just mand
          , E.occurrenceTitle       = title
          , E.occurrenceDescription = desc
          , E.occurrencePhotoUrl    = photo
          , E.occurrenceLatitude    = Just lat
          , E.occurrenceLongitude   = Just lng
          , E.occurrenceCep         = cep
          , E.occurrenceCity        = city
          , E.occurrenceUf          = uf
          , E.occurrenceStatus      = status
          , E.occurrenceCreatedAt   = addUTCTime (negate (fromInteger daysAgo * 86400)) now
          , E.occurrenceResolvedAt  = if status == "resolved" then Just (addUTCTime (negate (fromInteger resolved * 86400)) now) else Nothing
          }

  let occs =
        --      owner cat   mand   title                                    desc                                                              photo                                                                       lat        lng        cep        city               uf   status         daysAgo  resolvedDaysAgo
        [ mkOcc uid   buraco manSp "Buraco enorme na Av. Paulista"          "Buraco fundo na altura do MASP, ja danificou pneus."             "https://images.unsplash.com/photo-1542379653-b204bcb55ae6?w=800"            (-23.5613) (-46.6565) "01310100" "Sao Paulo"        "SP" "open"          1   0
        , mkOcc uid   luz    manSp "Poste apagado ha 3 semanas"             "Rua escura, perigosa pra quem volta do trabalho."                "https://images.unsplash.com/photo-1518709594023-6eab9bab7b23?w=800"          (-23.5400) (-46.6300) "01310200" "Sao Paulo"        "SP" "in_progress"   5   0
        , mkOcc uid   lixo   manSp "Lixo acumulado na praca"                "Cacamba sem coleta ha dias. Esta atraindo ratos."                "https://images.unsplash.com/photo-1604187351574-c75ca79f5807?w=800"          (-23.5500) (-46.6400) "01310300" "Sao Paulo"        "SP" "in_progress"   3   0
        , mkOcc uid   cal    manSp "Calcada quebrada em frente a escola"    "Calcada destruida, ja ouve queda de uma idosa."                  "https://images.unsplash.com/photo-1601132359864-c974e79890ac?w=800"          (-23.5700) (-46.6500) "01310400" "Sao Paulo"        "SP" "resolved"     30  2
        , mkOcc uid   esgoto manSp "Esgoto vazando na rua"                  "Mau cheiro insuportavel, vizinhos reclamam."                     "https://images.unsplash.com/photo-1611273426858-450d8e3c9fce?w=800"          (-23.5650) (-46.6450) "01310500" "Sao Paulo"        "SP" "open"          7   0
        , mkOcc uid   buraco manSp "Bueiro entupido apos chuva"             "Alagamento toda vez que chove."                                  "https://images.unsplash.com/photo-1591035897819-f4bdf739f446?w=800"          (-23.5450) (-46.6550) "01310600" "Sao Paulo"        "SP" "resolved"     15  5
        , mkOcc uid   luz    manSp "Semaforo quebrado ha 1 mes"             "Cruzamento perigoso, ja houve 2 acidentes."                      "https://images.unsplash.com/photo-1597007030739-6d2e7172ee27?w=800"          (-23.5550) (-46.6700) "05425001" "Sao Paulo"        "SP" "resolved"     40  10
        -- Rio
        , mkOcc uid   buraco manRj "Cratera na Av. Atlantica"               "Buraco gigante perto do calcadao de Copacabana."                  "https://images.unsplash.com/photo-1518391846015-55a9cc003b25?w=800"         (-22.9706) (-43.1822) "22021001" "Rio de Janeiro"   "RJ" "open"          2   0
        , mkOcc uid   lixo   manRj "Container de lixo virado"               "Lixo espalhado pela calcada, ninguem recolheu."                  "https://images.unsplash.com/photo-1604187351574-c75ca79f5807?w=800"          (-22.9810) (-43.1900) "22411040" "Rio de Janeiro"   "RJ" "in_progress"   4   0
        , mkOcc uid   cal    manRj "Calcada afundou em Ipanema"             "Risco de tropeco, ja machucou pedestres."                        "https://images.unsplash.com/photo-1601132359864-c974e79890ac?w=800"          (-22.9870) (-43.2050) "22420000" "Rio de Janeiro"   "RJ" "open"          6   0
        , mkOcc uid   luz    manRj "Poste caido apos vendaval"              "Cabos no chao, perigo eletrico."                                 "https://images.unsplash.com/photo-1518709594023-6eab9bab7b23?w=800"          (-22.9750) (-43.1850) "22021100" "Rio de Janeiro"   "RJ" "resolved"     20  8
        -- BH
        , mkOcc uid   buraco manBh "Buraco fechou ha 2 meses, abriu de novo" "Reparo malfeito, ja era esperado."                              "https://images.unsplash.com/photo-1542379653-b204bcb55ae6?w=800"            (-19.9167) (-43.9345) "30130100" "Belo Horizonte"   "MG" "open"          1   0
        , mkOcc uid   esgoto manBh "Vazamento de agua na rua principal"     "Agua jorrando ha 2 dias, ninguem aparece pra arrumar."           "https://images.unsplash.com/photo-1582719188393-bb71ca45dbb9?w=800"          (-19.9200) (-43.9400) "30130200" "Belo Horizonte"   "MG" "in_progress"   2   0
        , mkOcc uid   lixo   manBh "Caliza de obra abandonada"              "Empresa nao retirou os entulhos."                                "https://images.unsplash.com/photo-1604187351574-c75ca79f5807?w=800"          (-19.9100) (-43.9500) "30130300" "Belo Horizonte"   "MG" "resolved"     25  3
        , mkOcc uid   cal    manBh "Arvore caida bloqueando passagem"       "Tempestade derrubou ha 3 dias."                                  "https://images.unsplash.com/photo-1599946347371-68eb71b16afc?w=800"          (-19.9300) (-43.9300) "30130400" "Belo Horizonte"   "MG" "resolved"     8   1
        , mkOcc uid   luz    manBh "Iluminacao publica fraca demais"        "Lampadas amareladas e fracas, sensacao de inseguranca."          "https://images.unsplash.com/photo-1518709594023-6eab9bab7b23?w=800"          (-19.9250) (-43.9350) "30130500" "Belo Horizonte"   "MG" "open"          3   0
        ]

  ocIds <- mapM (\occ -> runSqlPool (insert occ) pool) occs
  Logs.logInfo $ "  + " ++ show (length ocIds) ++ " ocorrencias"

  -- 5) votos distribuidos (mais nas ocorrencias dramaticas)
  let voteRules = [(0,4),(1,5),(2,3),(4,2),(5,6),(7,7),(9,3),(11,4),(12,5),(14,2)]
  forM_ voteRules $ \(occIdx, voters) -> do
    case safeIndex occIdx ocIds of
      Nothing -> return ()
      Just occId -> do
        let voters' = take voters uids
        forM_ voters' $ \v -> runSqlPool (insert_ (E.Vote v occId now)) pool
  Logs.logInfo "  + votos distribuidos"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Insere o user se nao existir; retorna o id existente caso ja exista.
ensureUser :: ConnectionPool -> E.User -> IO E.UserId
ensureUser pool u = do
  existing <- runSqlPool (getBy (E.UniqueUsername (E.userUsername u))) pool
  case existing of
    Just (Entity uid _) -> return uid
    Nothing -> runSqlPool (insert u) pool

fromMaybeKey :: Maybe E.CategoryId -> E.CategoryId
fromMaybeKey (Just k) = k
fromMaybeKey Nothing  = error "seed: categoria base esperada nao encontrada (rode seedDefaultCategories antes)"

safeIndex :: Int -> [a] -> Maybe a
safeIndex i xs = if i < length xs then Just (xs !! i) else Nothing

extraUsers :: [(String, String, String, String, String)]
extraUsers =
  [ ("Mariana Costa",   "mari",   "01310100", "Sao Paulo",      "SP")
  , ("Pedro Henrique",  "phenri", "01310200", "Sao Paulo",      "SP")
  , ("Juliana Reis",    "juli",   "22021001", "Rio de Janeiro", "RJ")
  , ("Rafael Mendes",   "rafa",   "30130100", "Belo Horizonte", "MG")
  , ("Camila Tavares",  "camila", "01310300", "Sao Paulo",      "SP")
  , ("Lucas Pinheiro",  "lucas",  "22420000", "Rio de Janeiro", "RJ")
  , ("Fernanda Alves",  "fer",    "30130200", "Belo Horizonte", "MG")
  ]
