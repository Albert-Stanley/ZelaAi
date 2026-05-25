# ZelaAi — Frontend

Frontend em Vanilla JS + HTML + CSS. Mobile-first.

## Estrutura

```
front/
├── index.html            Feed público + mapa + modal de criar ocorrência
├── login.html            Login + Cadastro
├── occurrence.html       Detalhe da ocorrência + voto
├── css/
│   └── style.css         Estilos (tema verde, mobile-first)
└── js/
    ├── api.js            Cliente HTTP da API (todos endpoints encapsulados)
    ├── auth.js           Sessão local (JWT no localStorage) + helper toast
    ├── login.js          Lógica do login/cadastro
    ├── feed.js           Lógica do feed + mapa + criar ocorrência
    └── occurrence.js     Lógica do detalhe + voto
```

## Como rodar

### 1. Backend de pé

```bash
# no terminal 1
cd /Users/marcelosilva/ZelaAi
./zelaai.sh start
```

### 2. Servir o front

Como usa `type="module"` no JS, **não pode abrir o HTML direto (file://)**. Precisa de um servidor HTTP.

```bash
# no terminal 2
cd /Users/marcelosilva/ZelaAi/front
python3 -m http.server 8080
```

Depois abre no navegador: <http://localhost:8080/login.html>

## Roteiro de teste end-to-end (manual)

1. **Abre** `http://localhost:8080/login.html` — deve mostrar a tela com tabs *Entrar* / *Cadastrar*.
2. **Cadastra** clicando em *Cadastrar*. Preenche nome, username, senha (≤20 chars), CEP (8 dígitos, ex.: `01310100`). Submit → toast "Conta criada".
3. **Faz login** com username/senha que acabou de criar → redireciona pra `index.html`.
4. **Feed**: header mostra `@seuuser`. Mapa carrega (centrado em SP por padrão).
5. **Cria ocorrência** clicando no botão flutuante **+**. Preenche categoria, título, descrição, URL de foto (ex.: `https://picsum.photos/600/400`). Submit → toast "Ocorrência publicada".
6. **Volta automaticamente pro feed** com o card novo aparecendo.
7. **Clica no card** → abre `occurrence.html?id=N`.
8. **Vota** clicando em "Votar" → contador sobe.
9. **Vota de novo** → toast "você já votou nessa".
10. **Tira o voto** → contador desce.
11. **Sair** clica em "sair" no header → volta pro login.
12. **Recarrega** `/login.html` → mostra login direto (sessão limpa).

## Resolução de problemas

### Não carrega nada / CORS error no console
- Backend não tem CORS habilitado: rebuilda (`./zelaai.sh build`) e sobe de novo.
- Front está aberto via `file://` em vez de `http://`: use `python3 -m http.server`.

### "rede indisponível — backend offline"
- Servidor não está em `:5050`. Roda `./zelaai.sh start`.

### Mapa não aparece
- Verifica se há internet (Leaflet busca tiles do OSM).

### Foto não aparece no card
- A URL pode estar quebrada. O `<img>` é escondido se der erro. Use URLs públicas tipo `https://picsum.photos/600/400`.

### Quero limpar tudo e começar de novo
```bash
./zelaai.sh fresh
```
Isso dropa todas as tabelas e recria. Você vai precisar cadastrar de novo.
