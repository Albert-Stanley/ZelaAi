{-# LANGUAGE OverloadedStrings #-}

-- | Seed automatico de dados de demo.
-- Roda no startup APENAS se a tabela occurrence estiver vazia.
-- Idempotente: re-rodar nao duplica nada.
-- Pode ser desligado com SEED_DEMO=false.
module UseCase.SeedCase (seedDemoIfEmpty, seedTopupIfFew) where

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
  -- 1) usuario admin
  hashedAdmin <- Libs.hashPassword "admin1234"
  let adminUser = E.User
        { E.userName      = "Admin ZelaAi"
        , E.userUsername  = "admin"
        , E.userPassword  = hashedAdmin
        , E.userCep       = "01310100"
        , E.userCity      = "Sao Paulo"
        , E.userUf        = "SP"
        , E.userCreatedAt = now
        , E.userRole      = "admin"
        }
  _ <- ensureUser pool adminUser
  Logs.logInfo "  + user @admin (senha: admin1234, role=admin)"

  -- 2) usuario demo
  hashed <- Libs.hashPassword "demo1234"
  let demoUser = E.User
        { E.userName      = "Cidadao Demo"
        , E.userUsername  = "demo"
        , E.userPassword  = hashed
        , E.userCep       = "01310100"
        , E.userCity      = "Sao Paulo"
        , E.userUf        = "SP"
        , E.userCreatedAt = now
        , E.userRole      = "citizen"
        }
  uid <- ensureUser pool demoUser
  Logs.logInfo "  + user @demo (senha: demo1234)"

  -- usuarios extras pra dar volume nos votos
  uids <- mapM (\(n, un, cep, c, u) -> do
    h <- Libs.hashPassword "demo1234"
    ensureUser pool E.User
      { E.userName = n, E.userUsername = un, E.userPassword = h
      , E.userCep = cep, E.userCity = c, E.userUf = u, E.userCreatedAt = now
      , E.userRole = "citizen" }
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
          , E.occurrenceDeletedAt   = Nothing
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

-- ---------------------------------------------------------------------------
-- Top-up aditivo: roda no boot e enche o banco com mais ocorrencias se
-- houver poucas (ex: 18 do seed inicial). Idempotente.
-- ---------------------------------------------------------------------------

-- | Threshold: se ja tiver MAIS que isso, nao adiciona nada.
topupTarget :: Int
topupTarget = 50

seedTopupIfFew :: ConnectionPool -> IO ()
seedTopupIfFew pool = do
  enabled <- seedEnabled
  if not enabled then return () else do
    n <- runSqlPool (count ([] :: [Filter E.Occurrence])) pool
    if n >= topupTarget
      then Logs.logInfo $ "seed-topup: skipped (" ++ show n ++ " >= " ++ show topupTarget ++ ")"
      else do
        Logs.logInfo $ "seed-topup: ampliando dataset (" ++ show n ++ " -> ~" ++ show topupTarget ++ ")"
        now <- getCurrentTime
        runTopup pool now
        n2 <- runSqlPool (count ([] :: [Filter E.Occurrence])) pool
        Logs.logInfo $ "seed-topup: agora com " ++ show n2 ++ " ocorrencias"

runTopup :: ConnectionPool -> UTCTime -> IO ()
runTopup pool now = do
  -- 1) localiza recursos ja inseridos pelo seed inicial
  Just (Entity demoUid _) <- runSqlPool (getBy (E.UniqueUsername "demo")) pool
  extraUids <- mapM (\(_, un, _, _, _) -> do
      mU <- runSqlPool (getBy (E.UniqueUsername un)) pool
      case mU of
        Just (Entity uid _) -> return uid
        Nothing             -> return demoUid
    ) extraUsers
  cats <- runSqlPool (selectList ([] :: [Filter E.Category]) []) pool
  let catId name = case filter (\(Entity _ c) -> E.categoryName c == name) cats of
        (Entity cid _:_) -> cid
        _                -> error "seed-topup: categoria inesperadamente ausente"
      bur = catId "Buraco"
      luz = catId "Iluminacao"
      esg = catId "Esgoto"
      lix = catId "Lixo"
      cal = catId "Calcada"
  mandates <- runSqlPool (selectList ([] :: [Filter E.Mandate]) []) pool
  let findMandate c u = case filter (\(Entity _ m) -> E.mandateCity m == c && E.mandateUf m == u) mandates of
        (Entity mid _:_) -> Just mid
        _                -> Nothing
      mSp = findMandate "Sao Paulo" "SP"
      mRj = findMandate "Rio de Janeiro" "RJ"
      mBh = findMandate "Belo Horizonte" "MG"

  -- 2) ocorrencias adicionais variadas
  let allUsers = demoUid : extraUids
      pickUser i = allUsers !! (i `mod` length allUsers)
      photos = [ "https://images.unsplash.com/photo-1542379653-b204bcb55ae6?w=800"
               , "https://images.unsplash.com/photo-1518709594023-6eab9bab7b23?w=800"
               , "https://images.unsplash.com/photo-1604187351574-c75ca79f5807?w=800"
               , "https://images.unsplash.com/photo-1601132359864-c974e79890ac?w=800"
               , "https://images.unsplash.com/photo-1611273426858-450d8e3c9fce?w=800"
               , "https://images.unsplash.com/photo-1591035897819-f4bdf739f446?w=800"
               , "https://images.unsplash.com/photo-1597007030739-6d2e7172ee27?w=800"
               , "https://images.unsplash.com/photo-1518391846015-55a9cc003b25?w=800"
               , "https://images.unsplash.com/photo-1582719188393-bb71ca45dbb9?w=800"
               , "https://images.unsplash.com/photo-1599946347371-68eb71b16afc?w=800"
               ]
      pickPhoto i = photos !! (i `mod` length photos)
      mkOcc owner cat mand title desc lat lng cep city uf status daysAgo resolved photoIdx =
        E.Occurrence
          { E.occurrenceUserId      = owner
          , E.occurrenceCategoryId  = cat
          , E.occurrenceMandateId   = mand
          , E.occurrenceTitle       = title
          , E.occurrenceDescription = desc
          , E.occurrencePhotoUrl    = pickPhoto photoIdx
          , E.occurrenceLatitude    = Just lat
          , E.occurrenceLongitude   = Just lng
          , E.occurrenceCep         = cep
          , E.occurrenceCity        = city
          , E.occurrenceUf          = uf
          , E.occurrenceStatus      = status
          , E.occurrenceCreatedAt   = addUTCTime (negate (fromInteger daysAgo * 86400)) now
          , E.occurrenceResolvedAt  =
              if status == "resolved"
                then Just (addUTCTime (negate (fromInteger resolved * 86400)) now)
                else Nothing
          , E.occurrenceDeletedAt   = Nothing
          }

  -- 18 novas em SP -----------------------------------------------------------
  let spOccs = map (\(i, (cat, t, d, lat, lng, cep, st, da, re)) ->
                     mkOcc (pickUser i) cat mSp t d lat lng cep "Sao Paulo" "SP" st da re i)
                   (zip [0..]
        [ (bur, "Buraco gigante na Marginal Tiete",          "Trafego desviado por causa do buraco, ja causou 3 acidentes.", -23.5180, -46.7080, "02100000", "open",         2,  0)
        , (luz, "Iluminacao apagada na Av. Sumare",          "Quase a metade dos postes da via apagados ha 1 semana.",       -23.5390, -46.6800, "01253000", "in_progress",  6,  0)
        , (esg, "Esgoto a ceu aberto na Penha",              "Tem 3 casas afetadas pelo mau cheiro, criancas adoecendo.",    -23.5300, -46.5500, "03600000", "open",         3,  0)
        , (lix, "Caliza acumulada no Brooklin",              "Caminhao nao passa ha 10 dias, lixo subindo ate o joelho.",    -23.6100, -46.6800, "04568000", "in_progress",  10, 0)
        , (cal, "Calcada toda quebrada na Rua Bela Cintra",  "Pe direito ja causou queda em 2 idosos da regiao.",            -23.5560, -46.6620, "01415000", "resolved",     35, 5)
        , (bur, "Tampa de bueiro faltando",                  "Bueiro aberto no meio da rua, perigo gigante a noite.",        -23.5470, -46.6440, "01310180", "open",         1,  0)
        , (luz, "Semaforo intermitente em Pinheiros",        "Pisca constante, motoristas confusos sem saber se passa.",     -23.5650, -46.6900, "05418000", "resolved",     22, 3)
        , (esg, "Vazamento de agua na Vila Madalena",        "Agua jorrando direto do asfalto, ja escorre rua abaixo.",      -23.5500, -46.6900, "05433000", "in_progress",  4,  0)
        , (lix, "Lixao informal na Mooca",                   "Terreno baldio virou deposito improvisado de entulho.",        -23.5500, -46.6000, "03103000", "open",         15, 0)
        , (cal, "Arvore caida apos chuva forte",             "Bloqueando totalmente a passagem na calcada.",                 -23.5310, -46.6580, "01230000", "resolved",     8,  1)
        , (bur, "Cratera apos chuva na Vila Olimpia",        "Asfalto cedeu, abriu cratera de 2 metros de diametro.",        -23.5950, -46.6850, "04547000", "open",         5,  0)
        , (luz, "Praca sem iluminacao no Tatuape",           "Crianca caiu no escuro tentando atravessar a praca a noite.",  -23.5380, -46.5760, "03316000", "in_progress",  12, 0)
        , (esg, "Boca de lobo entupida no centro",           "Apos chuva, agua transbordou na esquina toda.",                -23.5489, -46.6388, "01001000", "resolved",     18, 2)
        , (lix, "Sacos de lixo rasgados pela rua",           "Cachorros mexem nos sacos, espalham tudo na calcada.",         -23.5640, -46.6580, "01415100", "open",         2,  0)
        , (cal, "Buraco enorme na ciclovia de Higienopolis", "Ciclista cai toda semana, prefeitura nao tampou ainda.",       -23.5410, -46.6580, "01230020", "in_progress",  9,  0)
        , (bur, "Asfalto irregular em Santana",              "Tres trechos consecutivos, e perigoso pra moto.",              -23.5040, -46.6240, "02012000", "open",         7,  0)
        , (luz, "Refletor queimado do campo do CDC",         "Crianca da regiao nao consegue mais treinar a noite.",         -23.5300, -46.6740, "05003000", "resolved",     45, 8)
        , (cal, "Calcada elevada na altura do metro Sao Bento", "Pedestres tropecam, ja tem placa caida ha tempo.",         -23.5440, -46.6340, "01016000", "open",         11, 0)
        ])

  -- 13 novas em RJ -----------------------------------------------------------
      rjOccs = map (\(i, (cat, t, d, lat, lng, cep, st, da, re)) ->
                     mkOcc (pickUser (i + 20)) cat mRj t d lat lng cep "Rio de Janeiro" "RJ" st da re (i + 100))
                   (zip [0..]
        [ (bur, "Buraco enorme no Leblon",                  "Esquina da Visconde, ja danificou suspensao de varios carros.", -22.9840, -43.2230, "22440002", "open",         3,  0)
        , (luz, "Tunel sem luz na Lagoa",                   "Trafego perigoso, ninguem ve nada a noite.",                    -22.9700, -43.2000, "22041030", "in_progress",  8,  0)
        , (esg, "Esgoto vazando na Avenida das Americas",   "Mau cheiro afeta toda a quadra, vizinhos exigem reparo.",      -23.0020, -43.3490, "22640000", "open",         5,  0)
        , (lix, "Container queimado em Madureira",          "Alguem ateou fogo no lixo, container destruido.",              -22.8770, -43.3380, "21356000", "resolved",     30, 4)
        , (cal, "Calcada apagada em Botafogo",              "Pedestres caminham na rua, perigo pra ciclista e motorista.", -22.9550, -43.1900, "22260000", "in_progress",  6,  0)
        , (bur, "Asfalto cedendo na Tijuca",                "Rua afunda visivelmente apos cada chuva.",                     -22.9270, -43.2360, "20510000", "open",         2,  0)
        , (luz, "Praia de Copacabana com posts apagados",   "Frente da praia escura, turistas relatam inseguranca.",         -22.9700, -43.1850, "22021100", "open",         4,  0)
        , (esg, "Boca de esgoto entupida em Sao Cristovao", "Agua nao escoa, alagamento total apos qualquer pancada.",      -22.8970, -43.2230, "20950000", "resolved",     21, 3)
        , (lix, "Lixo amontoado em Bonsucesso",             "Coleta atrasada ha 1 semana, mau cheiro generalizado.",        -22.8580, -43.2530, "21041000", "open",         9,  0)
        , (cal, "Calcada esburacada em Ipanema",            "Risco de tropeco em frente ao posto 9 da praia.",              -22.9870, -43.2050, "22420010", "in_progress",  3,  0)
        , (bur, "Buraco profundo em Vila Isabel",           "Carro caiu hoje, motorista bateu cabeca.",                     -22.9180, -43.2350, "20541170", "open",         1,  0)
        , (luz, "Poste sem lampada na Barra",               "Esquina perigosa, mulheres evitam passar a noite.",            -23.0030, -43.3650, "22641000", "in_progress",  14, 0)
        , (esg, "Vazamento de agua em Niteroi",             "Agua escapa pela parede do predio publico.",                   -22.8830, -43.1040, "24020091", "resolved",     16, 2)
        ])

  -- 11 novas em BH -----------------------------------------------------------
      bhOccs = map (\(i, (cat, t, d, lat, lng, cep, st, da, re)) ->
                     mkOcc (pickUser (i + 50)) cat mBh t d lat lng cep "Belo Horizonte" "MG" st da re (i + 200))
                   (zip [0..]
        [ (bur, "Cratera na Avenida do Contorno",           "Bloqueia uma faixa inteira, transito caotico no horario de pico.", -19.9300, -43.9410, "30110000", "open",         4,  0)
        , (luz, "Iluminacao falha no Buritis",              "Bairro inteiro com lampadas apagadas, moradores reclamam.",       -19.9870, -43.9700, "30575010", "in_progress",  9,  0)
        , (esg, "Cheiro forte de esgoto no Barreiro",       "Esgoto a ceu aberto perto do supermercado da regiao.",            -19.9740, -44.0140, "30640610", "open",         6,  0)
        , (lix, "Lixao improvisado em Venda Nova",          "Empresarios da regiao reclamam do impacto na imagem.",            -19.8200, -43.9540, "31610190", "resolved",     28, 4)
        , (cal, "Calcada destruida em Savassi",             "Cratera em frente ao shopping, perigo pra pedestre.",             -19.9380, -43.9420, "30130150", "in_progress",  5,  0)
        , (bur, "Buraco profundo na Pampulha",              "Ja danificou 2 viaturas da policia.",                            -19.8580, -43.9700, "31330610", "open",         3,  0)
        , (luz, "Sinaleiro quebrado no centro de BH",       "Apaga e acende sem padrao, motoristas se confundem.",             -19.9170, -43.9380, "30130100", "resolved",     19, 3)
        , (esg, "Esgoto entupido na Lagoinha",              "Apos chuva, esgoto sobe e invade casas.",                        -19.9100, -43.9450, "31110030", "open",         2,  0)
        , (lix, "Container caido em Floresta",              "Ja faz 5 dias, ninguem da prefeitura passa.",                    -19.9080, -43.9300, "31015000", "in_progress",  5,  0)
        , (cal, "Calcada toda fissurada na Cidade Nova",    "Pedestres precisam andar pela rua, varios escorregos relatados.", -19.8950, -43.9180, "31170140", "open",         8,  0)
        , (bur, "Buraco no asfalto em Belvedere",           "Apos obra mal feita, asfalto rachou novamente.",                  -19.9610, -43.9420, "30320130", "resolved",     33, 6)
        ])

  let allOccs = spOccs ++ rjOccs ++ bhOccs
  ocIds <- mapM (\occ -> runSqlPool (insert occ) pool) allOccs
  Logs.logInfo $ "  + " ++ show (length ocIds) ++ " ocorrencias adicionais"

  -- votos extras nas mais "dramaticas"
  let voteUserIds = take 6 extraUids
      pickedOccs  = take 18 ocIds
  forM_ (zip pickedOccs (cycle [3,5,2,4,6,3,7,2,4,5,3,6,2,4,3,5,2,4])) $ \(occId, numVotes) ->
    forM_ (take numVotes voteUserIds) $ \v ->
      runSqlPool (insert_ (E.Vote v occId now)) pool
  Logs.logInfo "  + votos extras distribuidos"

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
