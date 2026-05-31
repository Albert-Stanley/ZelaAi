import { Api } from "./api.js";
import { Auth, toast } from "./auth.js";
import { Theme } from "./theme.js";
import { attachCepLookup } from "./cep.js";
import { attachUploader, cloudinaryConfigured } from "./upload.js";
import { mountKeyboardShortcuts } from "./keys.js";
import { startOnboarding } from "./onboarding.js";
import { escapeHtml, escapeAttr, labelStatus, statusColor, fmtDateTime, timeAgo, fallbackImage as fallbackImageUtil } from "./util.js";

// Feed é PÚBLICO — não exige login. Só esconde o FAB se não tiver sessão.
const isLogged = Auth.isLogged();
const user = Auth.user();

const userTag    = document.getElementById("user-tag");
const logoutLink = document.getElementById("logout-link");
const myLink     = document.getElementById("my-link");
const fabNew     = document.getElementById("fab-new");

if (isLogged) {
  userTag.textContent = `@${user.userUsername}`;
  logoutLink.style.display = "";
  if (myLink) myLink.style.display = "";
  fabNew.style.display = "";
} else {
  userTag.innerHTML = `<a href="login.html" style="color:white;text-decoration:underline;font-weight:600;">Entrar</a>`;
  logoutLink.style.display = "none";
  if (myLink) myLink.style.display = "none";
  fabNew.style.display = "none";
}

logoutLink.addEventListener("click", (e) => {
  e.preventDefault();
  Auth.logout();
  window.location.reload();
});

// monta theme toggle no header
Theme.mountToggle(document.querySelector(".header-actions"));

// ------------------------------- Mapa --------------------------------------
// Inicialização preguiçosa via IntersectionObserver e atualização de markers
// com requestIdleCallback para não travar o scroll.

let map = null;
let markerLayer = null;
let pendingOccs = null;

function initMap() {
  if (map) return;
  map = L.map("map", {
    zoomControl: true,
    attributionControl: false,
    preferCanvas: true,            // canvas é mais rápido pra muitos markers
    fadeAnimation: false,
    zoomAnimation: true,
    wheelDebounceTime: 60,
  }).setView([-23.55, -46.63], 12);

  L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
    attribution: "© OpenStreetMap, © CARTO",
    maxZoom: 19,
    subdomains: "abcd",
    crossOrigin: true,
    detectRetina: true,
  }).addTo(map);

  L.control.attribution({ prefix: false, position: "bottomright" })
    .addAttribution("© OSM · CARTO").addTo(map);

  markerLayer = L.layerGroup().addTo(map);

  // re-render quando o tema muda (filtro CSS nas tiles já é aplicado automaticamente)
  if (pendingOccs) {
    drawMarkers(pendingOccs);
    pendingOccs = null;
  }
  // garante que o leaflet recalcule tamanho
  requestAnimationFrame(() => map.invalidateSize());
}

const mapEl = document.getElementById("map");
const mapWrap = mapEl.closest(".map-wrap");

// botão de colapsar/expandir mapa
const mapToggleBtn = document.createElement("button");
mapToggleBtn.type = "button";
mapToggleBtn.className = "map-toggle";
mapToggleBtn.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg> Recolher`;
mapWrap.appendChild(mapToggleBtn);

const COLLAPSED_KEY = "zelaai.mapCollapsed";
if (localStorage.getItem(COLLAPSED_KEY) === "1") {
  mapWrap.classList.add("collapsed");
  mapToggleBtn.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg> Mostrar mapa`;
}
mapToggleBtn.addEventListener("click", () => {
  const collapsed = mapWrap.classList.toggle("collapsed");
  localStorage.setItem(COLLAPSED_KEY, collapsed ? "1" : "0");
  mapToggleBtn.innerHTML = collapsed
    ? `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg> Mostrar mapa`
    : `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg> Recolher`;
  if (!collapsed && map) requestAnimationFrame(() => map.invalidateSize());
});

// botão "Próximas a mim" (geo-search)
const nearbyBtn = document.createElement("button");
nearbyBtn.type = "button";
nearbyBtn.className = "map-nearby";
nearbyBtn.innerHTML = `
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/><line x1="12" y1="2" x2="12" y2="5"/><line x1="12" y1="19" x2="12" y2="22"/><line x1="2" y1="12" x2="5" y2="12"/><line x1="19" y1="12" x2="22" y2="12"/></svg>
  Próximas a mim
`;
mapWrap.appendChild(nearbyBtn);

let nearbyMode = false;
let nearbyMarker = null;
nearbyBtn.addEventListener("click", async () => {
  if (nearbyMode) {
    nearbyMode = false;
    nearbyBtn.classList.remove("active");
    nearbyBtn.querySelector("svg")?.nextSibling && (nearbyBtn.lastChild.textContent = " Próximas a mim");
    if (nearbyMarker && map) { map.removeLayer(nearbyMarker); nearbyMarker = null; }
    applyFilter();
    return;
  }
  if (!navigator.geolocation) { toast("geolocalização indisponível", "error"); return; }
  nearbyBtn.classList.add("loading");
  navigator.geolocation.getCurrentPosition(async pos => {
    try {
      const { latitude: lat, longitude: lng } = pos.coords;
      const results = await Api.nearbyOccurrences(lat, lng, 5);
      nearbyMode = true;
      nearbyBtn.classList.add("active");
      nearbyBtn.lastChild.textContent = ` ${results.length} a ≤5km · limpar`;
      // substitui o feed e markers pela versão nearby
      const occs = results.map(r => r.nearOcc);
      countEl.textContent = `${results.length} próximas`;
      if (occs.length === 0) {
        feedEl.innerHTML = `<div class="empty">Nenhuma ocorrência num raio de 5km de você.</div>`;
      } else {
        // adiciona distância no card
        feedEl.innerHTML = results.map(r => cardWithDistance(r)).join("");
      }
      if (map) {
        scheduleMarkerDraw(occs);
        // pin "você está aqui"
        if (nearbyMarker) map.removeLayer(nearbyMarker);
        nearbyMarker = L.circleMarker([lat, lng], {
          radius: 9, weight: 3, color: "#0d6efd", fillColor: "#0d6efd", fillOpacity: 0.4
        }).addTo(map).bindPopup("<b>Você está aqui</b>");
        map.setView([lat, lng], 14);
      }
    } catch (e) {
      toast(e.message || "erro no geo-search", "error");
    } finally {
      nearbyBtn.classList.remove("loading");
    }
  }, () => {
    nearbyBtn.classList.remove("loading");
    toast("permissão de localização negada", "error");
  }, { timeout: 6000 });
});

// ----------- Heatmap toggle ------------------------------------------------

const heatBtn = document.createElement("button");
heatBtn.type = "button";
heatBtn.className = "map-heat";
heatBtn.title = "Alternar heatmap";
heatBtn.innerHTML = `
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z"/></svg>
  Heatmap
`;
mapWrap.appendChild(heatBtn);

let heatLayer = null;
let heatMode = false;
let leafletHeatLoaded = false;

function loadLeafletHeat() {
  return new Promise((resolve, reject) => {
    if (leafletHeatLoaded) { resolve(); return; }
    const s = document.createElement("script");
    s.src = "https://unpkg.com/leaflet.heat@0.2.0/dist/leaflet-heat.js";
    s.onload = () => { leafletHeatLoaded = true; resolve(); };
    s.onerror = reject;
    document.head.appendChild(s);
  });
}

// ----------- Fullscreen map ------------------------------------------------

const fsBtn = document.createElement("button");
fsBtn.type = "button";
fsBtn.className = "map-fs";
fsBtn.title = "Ver mapa em tela cheia";
fsBtn.setAttribute("aria-label", "Tela cheia");
fsBtn.innerHTML = `
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M21 8V5a2 2 0 0 0-2-2h-3"/><path d="M3 16v3a2 2 0 0 0 2 2h3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/></svg>
  Tela cheia
`;
mapWrap.appendChild(fsBtn);

let fsOverlay = null;
function openFullscreenMap() {
  if (fsOverlay) return;
  fsOverlay = document.createElement("div");
  fsOverlay.className = "map-fs-overlay";
  fsOverlay.innerHTML = `
    <header class="map-fs-header">
      <button type="button" class="map-fs-back" id="map-fs-back" aria-label="Voltar">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
        <span>Voltar</span>
      </button>
      <div class="map-fs-title">
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
        <span>Mapa de ocorrências</span>
        <em id="map-fs-count">${allOccs.length} pinos</em>
      </div>
      <div class="map-fs-legend">
        <span class="map-fs-dot" style="background:#f59e0b"></span>Aberta
        <span class="map-fs-dot" style="background:#3b82f6"></span>Em andamento
        <span class="map-fs-dot" style="background:#0f9d58"></span>Resolvida
      </div>
    </header>
    <div class="map-fs-body" id="map-fs-body"></div>
  `;
  document.body.appendChild(fsOverlay);
  document.body.classList.add("map-fs-open");

  // move o #map para dentro do overlay (preserva o leaflet, evita re-init)
  const body = fsOverlay.querySelector("#map-fs-body");
  body.appendChild(mapEl);
  if (map) {
    requestAnimationFrame(() => {
      map.invalidateSize();
      // se markers visíveis, ajusta bounds; senão mantém view atual
      if (!heatMode && markerLayer && markerLayer.getLayers().length > 0) {
        const group = L.featureGroup(markerLayer.getLayers());
        try { map.fitBounds(group.getBounds(), { padding: [60, 60], maxZoom: 15 }); } catch {}
      }
    });
  }

  fsOverlay.querySelector("#map-fs-back").addEventListener("click", closeFullscreenMap);
}

function closeFullscreenMap() {
  if (!fsOverlay) return;
  // devolve o #map ao map-wrap original
  mapWrap.insertBefore(mapEl, mapWrap.firstChild);
  fsOverlay.remove();
  fsOverlay = null;
  document.body.classList.remove("map-fs-open");
  if (map) requestAnimationFrame(() => map.invalidateSize());
}

fsBtn.addEventListener("click", openFullscreenMap);

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && fsOverlay) {
    e.stopPropagation();
    closeFullscreenMap();
  }
}, true);

heatBtn.addEventListener("click", async () => {
  if (!map) { toast("aguarde o mapa carregar", "error"); return; }
  if (!heatMode) {
    heatBtn.classList.add("loading");
    try {
      await loadLeafletHeat();
      const points = (nearbyMode ? [] : allOccs)
        .filter(o => o.occLatitude != null && o.occLongitude != null)
        .map(o => [o.occLatitude, o.occLongitude, Math.min(1, 0.2 + o.occVoteCount * 0.05)]);
      if (points.length === 0) { toast("sem coordenadas para o heatmap", "error"); return; }
      if (heatLayer) map.removeLayer(heatLayer);
      heatLayer = L.heatLayer(points, { radius: 28, blur: 20, maxZoom: 17 }).addTo(map);
      markerLayer.remove();
      heatMode = true;
      heatBtn.classList.add("active");
    } catch {
      toast("erro ao carregar plugin de heatmap", "error");
    } finally {
      heatBtn.classList.remove("loading");
    }
  } else {
    if (heatLayer) { map.removeLayer(heatLayer); heatLayer = null; }
    markerLayer.addTo(map);
    heatMode = false;
    heatBtn.classList.remove("active");
  }
});

function cardWithDistance(r) {
  const o = r.nearOcc;
  const extraLoc = ` · <b style="color:var(--accent);">${r.nearDistance.toFixed(2)} km</b>`;
  return cardHtml(o, extraLoc);
}

// só carrega o mapa quando ele entra na viewport
const io = new IntersectionObserver((entries) => {
  entries.forEach(e => {
    if (e.isIntersecting && !mapWrap.classList.contains("collapsed")) {
      initMap();
      io.disconnect();
    }
  });
}, { rootMargin: "200px" });
io.observe(mapWrap);

function drawMarkers(occs) {
  if (!map || !markerLayer) { pendingOccs = occs; return; }
  markerLayer.clearLayers();
  const bounds = [];
  for (const o of occs) {
    if (o.occLatitude == null || o.occLongitude == null) continue;
    const m = L.circleMarker([o.occLatitude, o.occLongitude], {
      radius: 7,
      weight: 2,
      color: statusColor(o.occStatus),
      fillColor: statusColor(o.occStatus),
      fillOpacity: 0.7,
    });
    m.bindPopup(
      `<b>${escapeHtml(o.occTitle)}</b><br>` +
      `<small>${o.occVoteCount} voto(s) · ${labelStatus(o.occStatus)}</small><br>` +
      `<a href="occurrence.html?id=${o.occId}">ver detalhes →</a>`
    );
    markerLayer.addLayer(m);
    bounds.push([o.occLatitude, o.occLongitude]);
  }
  if (bounds.length === 1) map.setView(bounds[0], 14);
  else if (bounds.length > 1) map.fitBounds(bounds, { padding: [30, 30], maxZoom: 15 });
}

function scheduleMarkerDraw(occs) {
  // usa idle callback pra não competir com o scroll
  const cb = () => drawMarkers(occs);
  if ("requestIdleCallback" in window) requestIdleCallback(cb, { timeout: 500 });
  else setTimeout(cb, 50);
}

// ---------------------------- Feed (cards) ---------------------------------

const feedEl  = document.getElementById("feed");
const countEl = document.getElementById("count");
const searchInput = document.getElementById("search");
const chipsEl = document.getElementById("status-chips");

let allOccs = [];
let activeStatus = "all";

// ----- URL state ----------------------------------------------------------
// Sincroniza filtro (status) e busca (q) com a URL. Permite compartilhar
// links como ?status=resolved&q=buraco.
function readUrlState() {
  const u = new URL(window.location.href);
  const s = u.searchParams.get("status");
  const q = u.searchParams.get("q");
  if (s && ["all","open","in_progress","resolved"].includes(s)) activeStatus = s;
  if (q && searchInput) searchInput.value = q;
}
function writeUrlState() {
  const u = new URL(window.location.href);
  if (activeStatus && activeStatus !== "all") u.searchParams.set("status", activeStatus);
  else u.searchParams.delete("status");
  const q = (searchInput?.value || "").trim();
  if (q) u.searchParams.set("q", q);
  else u.searchParams.delete("q");
  history.replaceState(null, "", u.toString());
}
const PAGE_SIZE = 30;
let currentPage = 1;
let reachedEnd = false;
let loadingMore = false;

async function loadFeed() {
  feedEl.innerHTML = `<div class="skeleton skeleton-card"></div><div class="skeleton skeleton-card"></div>`;
  currentPage = 1;
  reachedEnd = false;
  readUrlState();
  // espelha activeStatus nos chips
  [chipsEl, sidebarChipsEl].forEach(el => {
    if (!el) return;
    el.querySelectorAll("button[data-status]").forEach(b => {
      b.classList.toggle("active", b.dataset.status === activeStatus);
    });
  });
  try {
    const first = await Api.listOccurrences({ page: 1, pageSize: PAGE_SIZE });
    allOccs = first;
    reachedEnd = first.length < PAGE_SIZE;
    applyFilter();
    renderSidebarTrending(allOccs);
    renderSidebarStats(allOccs);
  } catch (e) {
    feedEl.innerHTML = `<div class="empty">erro ao carregar: ${escapeHtml(e.message)}</div>`;
  }
}

async function loadMore() {
  if (loadingMore || reachedEnd) return;
  loadingMore = true;
  const btn = document.getElementById("load-more-btn");
  if (btn) { btn.disabled = true; btn.textContent = "Carregando…"; }
  try {
    const nextPage = currentPage + 1;
    const more = await Api.listOccurrences({ page: nextPage, pageSize: PAGE_SIZE });
    if (more.length === 0) {
      reachedEnd = true;
    } else {
      currentPage = nextPage;
      // dedup por id por garantia
      const known = new Set(allOccs.map(o => o.occId));
      const fresh = more.filter(o => !known.has(o.occId));
      allOccs = allOccs.concat(fresh);
      if (more.length < PAGE_SIZE) reachedEnd = true;
      applyFilter();
      renderSidebarTrending(allOccs);
      renderSidebarStats(allOccs);
    }
  } catch (e) {
    toast(e.message || "erro ao carregar mais", "error");
  } finally {
    loadingMore = false;
    const btn2 = document.getElementById("load-more-btn");
    if (btn2) { btn2.disabled = false; btn2.textContent = "Carregar mais"; }
  }
}

function applyFilter() {
  writeUrlState();
  const q = (searchInput.value || "").toLowerCase().trim();
  let filtered = allOccs;
  if (activeStatus !== "all") filtered = filtered.filter(o => o.occStatus === activeStatus);
  if (q) {
    filtered = filtered.filter(o =>
      (o.occTitle       || "").toLowerCase().includes(q) ||
      (o.occDescription || "").toLowerCase().includes(q) ||
      (o.occCity        || "").toLowerCase().includes(q) ||
      (o.occCep         || "").includes(q)
    );
  }

  countEl.textContent = (q || activeStatus !== "all")
    ? `${filtered.length} de ${allOccs.length}`
    : `${allOccs.length} ${allOccs.length === 1 ? "item" : "itens"}`;

  if (filtered.length === 0) {
    feedEl.innerHTML = (q || activeStatus !== "all")
      ? emptyStateHtml("search", "Nada encontrado", "Tente outras palavras-chave ou troque o filtro de status.")
      : emptyStateHtml("city", "Sua cidade está calma por aqui", isLogged
          ? "Seja a primeira voz: clique no botão <b>+</b> para reportar um problema."
          : '<a href="login.html">Entre</a> para reportar a primeira ocorrência.');
    scheduleMarkerDraw([]);
    return;
  }

  // renderiza usando DocumentFragment pra reduzir reflows
  const tpl = document.createElement("template");
  tpl.innerHTML = filtered.map(o => cardHtml(o)).join("");
  feedEl.replaceChildren(tpl.content);

  // Botão "carregar mais" — só mostra quando não há filtro de status/busca ativo
  // e ainda há mais páginas no servidor.
  const noFilter = !q && activeStatus === "all";
  if (noFilter && !reachedEnd) {
    const more = document.createElement("div");
    more.className = "load-more-wrap";
    more.innerHTML = `
      <button type="button" class="btn secondary" id="load-more-btn">Carregar mais</button>
      <span class="load-more-count">mostrando <b>${allOccs.length}</b> ocorrências (página ${currentPage})</span>
    `;
    feedEl.appendChild(more);
    more.querySelector("#load-more-btn").addEventListener("click", loadMore);
  } else if (noFilter && reachedEnd && allOccs.length > 0) {
    const end = document.createElement("div");
    end.className = "load-end";
    end.textContent = "— você chegou ao fim —";
    feedEl.appendChild(end);
  }

  // delegação de evento pra cliques no feed (1 listener em vez de N)
  scheduleMarkerDraw(filtered);
}

feedEl.addEventListener("click", async (e) => {
  const actionBtn = e.target.closest(".card-action");
  if (actionBtn) {
    const act = actionBtn.dataset.act;
    const card = actionBtn.closest(".card");
    const id = Number(card?.dataset.id);
    if (act === "open" || act === "comments") return; // links nativos
    e.stopPropagation();
    e.preventDefault();
    if (act === "toggle-comments") {
      await toggleInlineComments(card, id, actionBtn);
      return;
    }
    if (act === "vote") {
      if (!isLogged) { window.location.href = "login.html"; return; }
      const wasVoted = actionBtn.classList.contains("voted");
      actionBtn.disabled = true;
      try {
        const res = wasVoted
          ? await Api.unvote(id, Auth.token())
          : await Api.vote(id, Auth.token());
        actionBtn.classList.toggle("voted", !wasVoted);
        const cnt = actionBtn.querySelector(".card-action-count");
        if (cnt) cnt.textContent = res.voteCount;
        const occ = allOccs.find(x => x.occId === id);
        if (occ) { occ.occVoteCount = res.voteCount; occ.userHasVoted = !wasVoted; }
        toast(wasVoted ? "Voto removido" : "Voto computado!", "success");
      } catch (err) {
        if (err.status === 401) { Auth.logout(); window.location.href = "login.html"; return; }
        if (err.status === 409) toast("você já votou nessa", "error");
        else if (err.status === 404) toast("você não tinha votado", "error");
        else toast(err.message || "erro ao votar", "error");
      } finally { actionBtn.disabled = false; }
      return;
    }
    if (act === "share") {
      const occ = allOccs.find(x => x.occId === id);
      const url = `${window.location.origin}${window.location.pathname.replace(/[^/]*$/, "")}occurrence.html?id=${id}`;
      if (navigator.share) {
        navigator.share({ title: occ?.occTitle || "Ocorrência", text: occ?.occDescription || "", url }).catch(() => {});
      } else {
        navigator.clipboard?.writeText(url).then(
          () => toast("Link copiado!", "success"),
          () => toast("não foi possível copiar", "error")
        );
      }
      return;
    }
  }
  // clicks dentro do painel de comentários inline não navegam
  if (e.target.closest(".card-comments-panel")) return;
  const card = e.target.closest(".card");
  if (card && card.dataset.id) window.location.href = `occurrence.html?id=${card.dataset.id}`;
});

let searchTimer;
searchInput.addEventListener("input", () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(applyFilter, 180);
});

// chips de filtro de status (mobile, inline)
if (chipsEl) {
  chipsEl.addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-status]");
    if (!btn) return;
    setActiveStatus(btn.dataset.status);
  });
}

// chips de filtro de status (desktop sidebar)
const sidebarChipsEl = document.getElementById("status-chips-sidebar");
if (sidebarChipsEl) {
  sidebarChipsEl.addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-status]");
    if (!btn) return;
    setActiveStatus(btn.dataset.status);
  });
}

function setActiveStatus(status) {
  activeStatus = status;
  [chipsEl, sidebarChipsEl].forEach(el => {
    if (!el) return;
    el.querySelectorAll("button[data-status]").forEach(b => {
      b.classList.toggle("active", b.dataset.status === status);
    });
  });
  applyFilter();
}

// Sidebar trending: top 5 por voto
function renderSidebarTrending(occs) {
  const el = document.getElementById("sidebar-trending");
  if (!el) return;
  const top = [...occs].sort((a, b) => b.occVoteCount - a.occVoteCount).slice(0, 5);
  if (top.length === 0) {
    el.innerHTML = `<h4 class="sidebar-title">Em alta</h4><div class="sidebar-loading">sem dados</div>`;
    return;
  }
  el.innerHTML = `
    <h4 class="sidebar-title">Em alta</h4>
    ${top.map((o, i) => `
      <div class="sidebar-trending-item" onclick="location.href='occurrence.html?id=${o.occId}'">
        <span class="sidebar-trending-rank">${i + 1}</span>
        <div class="sidebar-trending-info">
          <div class="sidebar-trending-title">${escapeHtml(o.occTitle)}</div>
          <div class="sidebar-trending-meta">
            <span class="badge ${o.occStatus}" style="font-size:0.6rem;padding:1px 5px;">${labelStatus(o.occStatus)}</span>
            <span>${o.occVoteCount} voto${o.occVoteCount !== 1 ? "s" : ""}</span>
          </div>
        </div>
      </div>`
    ).join("")}
  `;
}

// Sidebar stats
function renderSidebarStats(occs) {
  const total = occs.length;
  const open  = occs.filter(o => o.occStatus === "open").length;
  const prog  = occs.filter(o => o.occStatus === "in_progress").length;
  const res   = occs.filter(o => o.occStatus === "resolved").length;
  const set = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
  set("ss-total", total);
  set("ss-open",  open);
  set("ss-prog",  prog);
  set("ss-res",   res);
}

// Botão "Perto de mim" da sidebar direita (delega para o nearbyBtn do mapa)
const sidebarNearbyBtn = document.getElementById("sidebar-nearby-btn");
if (sidebarNearbyBtn) {
  sidebarNearbyBtn.addEventListener("click", () => nearbyBtn.click());
}

function cardHtml(o, extraLoc = "") {
  const loc = o.occCity ? `${escapeHtml(o.occCity)}${o.occUf ? "/" + escapeHtml(o.occUf) : ""}` : "—";
  const photoUrl = o.occPhotoUrl || fallbackImage(o);
  const created = o.occCreatedAt ? fmtDateTime(o.occCreatedAt) : "";
  const createdAgo = o.occCreatedAt ? timeAgo(o.occCreatedAt) : "";
  return `
    <article class="card" data-id="${o.occId}">
      <div class="card-media">
        <img class="card-img" src="${escapeAttr(photoUrl)}" alt="" loading="lazy" decoding="async" onerror="this.onerror=null;this.src='${escapeAttr(fallbackImage(o))}'" />
        <span class="card-badge-status badge ${o.occStatus}">${labelStatus(o.occStatus)}</span>
        ${createdAgo ? `<span class="card-badge-time" title="${escapeAttr(created)}">
          <svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
          ${createdAgo}
        </span>` : ""}
      </div>
      <div class="card-body">
        <div class="card-loc">
          <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
          ${loc}${extraLoc}
        </div>
        <h3>${escapeHtml(o.occTitle)}</h3>
        <p>${escapeHtml(o.occDescription)}</p>
        ${created ? `<div class="card-date" title="${escapeAttr(created)}">Publicado em ${created}</div>` : ""}
        <div class="card-actions" data-id="${o.occId}">
          <button type="button" class="card-action ${o.userHasVoted ? "voted" : ""}" data-act="vote" aria-label="Votar">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg>
            <span class="card-action-count">${o.occVoteCount}</span>
          </button>
          <button type="button" class="card-action" data-act="toggle-comments" aria-label="Comentários" aria-expanded="false">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
            <span>Comentários</span>
            ${typeof o.commentCount === "number" ? `<span class="card-action-count">${o.commentCount}</span>` : ""}
          </button>
          <button type="button" class="card-action" data-act="share" aria-label="Compartilhar">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
            <span>Compartilhar</span>
          </button>
          <a class="card-action card-action-open" href="occurrence.html?id=${o.occId}" data-act="open" aria-label="Abrir">
            Abrir
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
          </a>
        </div>
      </div>
    </article>`;
}

// ---------- Inline comments on card --------------------------------------

async function toggleInlineComments(card, occId, btn) {
  if (!card) return;
  let panel = card.querySelector(".card-comments-panel");
  if (panel) {
    // toggle close
    const isOpen = panel.classList.toggle("open");
    btn.setAttribute("aria-expanded", isOpen ? "true" : "false");
    btn.classList.toggle("active", isOpen);
    return;
  }
  // criar painel
  panel = document.createElement("div");
  panel.className = "card-comments-panel open";
  panel.innerHTML = `<div class="card-comments-loading">carregando comentários…</div>`;
  card.querySelector(".card-body").appendChild(panel);
  btn.setAttribute("aria-expanded", "true");
  btn.classList.add("active");
  try {
    const list = await Api.listComments(occId, { page: 1, pageSize: 30 });
    renderInlineComments(panel, occId, list);
    // atualiza contador no botão
    const occ = allOccs.find(x => x.occId === occId);
    if (occ) occ.commentCount = list.length;
    let countEl = btn.querySelector(".card-action-count");
    if (!countEl) {
      countEl = document.createElement("span");
      countEl.className = "card-action-count";
      btn.appendChild(countEl);
    }
    countEl.textContent = list.length;
  } catch (err) {
    panel.innerHTML = `<div class="card-comments-empty">erro: ${escapeHtml(err.message || "falha ao carregar")}</div>`;
  }
}

function renderInlineComments(panel, occId, list) {
  const composer = isLogged
    ? `<form class="card-comment-form" data-occ="${occId}">
         <textarea required maxlength="1000" placeholder="Comentar como @${escapeHtml(user.userUsername)}…" rows="2"></textarea>
         <button type="submit" class="btn small">Publicar</button>
       </form>`
    : `<div class="card-comments-login"><a href="login.html">Entre</a> para comentar.</div>`;

  const items = list.length === 0
    ? `<div class="card-comments-empty">Seja a primeira voz. Comente aí 👇</div>`
    : list.map(c => `
        <article class="card-comment">
          <div class="card-comment-avatar">${escapeHtml((c.commentUsername[0] || "?").toUpperCase())}</div>
          <div class="card-comment-main">
            <div class="card-comment-head">
              <strong>@${escapeHtml(c.commentUsername)}</strong>
              <span>${cmTimeAgo(c.commentCreatedAt)}</span>
            </div>
            <div class="card-comment-body">${escapeHtml(c.commentBody)}</div>
          </div>
        </article>
      `).join("");

  panel.innerHTML = `
    <div class="card-comments-head">
      <span>${list.length} ${list.length === 1 ? "comentário" : "comentários"}</span>
      <a href="occurrence.html?id=${occId}#comments" class="card-comments-link">abrir tudo →</a>
    </div>
    <div class="card-comments-list">${items}</div>
    ${composer}
  `;

  const form = panel.querySelector(".card-comment-form");
  if (form) form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const ta = form.querySelector("textarea");
    const body = ta.value.trim();
    if (!body) return;
    const submitBtn = form.querySelector("button");
    submitBtn.disabled = true;
    submitBtn.textContent = "…";
    try {
      await Api.createComment(occId, body, Auth.token());
      const fresh = await Api.listComments(occId, { page: 1, pageSize: 30 });
      renderInlineComments(panel, occId, fresh);
      const card = panel.closest(".card");
      const cnt = card?.querySelector('.card-action[data-act="toggle-comments"] .card-action-count');
      if (cnt) cnt.textContent = fresh.length;
      const occ = allOccs.find(x => x.occId === occId);
      if (occ) occ.commentCount = fresh.length;
      toast("comentário publicado", "success");
    } catch (err) {
      if (err.status === 401) { Auth.logout(); window.location.href = "login.html"; return; }
      toast(err.message || "erro ao comentar", "error");
      submitBtn.disabled = false;
      submitBtn.textContent = "Publicar";
    }
  });
}

function cmTimeAgo(iso) {
  const d = new Date(iso);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "agora";
  if (diff < 3600) return `há ${Math.floor(diff/60)}min`;
  if (diff < 86400) return `há ${Math.floor(diff/3600)}h`;
  if (diff < 604800) return `há ${Math.floor(diff/86400)}d`;
  return d.toLocaleDateString("pt-BR");
}

function emptyStateHtml(kind, title, body) {
  const svgs = {
    search: `<svg viewBox="0 0 200 160" width="180" height="140" aria-hidden="true">
      <circle cx="80" cy="70" r="48" fill="none" stroke="var(--primary)" stroke-width="6" opacity="0.4"/>
      <line x1="115" y1="105" x2="160" y2="150" stroke="var(--primary)" stroke-width="6" stroke-linecap="round" opacity="0.6"/>
      <circle cx="80" cy="70" r="20" fill="var(--primary-soft)"/>
      <text x="80" y="78" text-anchor="middle" font-size="22" font-weight="700" fill="var(--primary)">?</text>
    </svg>`,
    city: `<svg viewBox="0 0 220 160" width="200" height="150" aria-hidden="true">
      <rect x="20" y="80" width="36" height="60" rx="3" fill="var(--primary)" opacity="0.85"/>
      <rect x="64" y="50" width="44" height="90" rx="3" fill="var(--primary-dark, #047857)" opacity="0.9"/>
      <rect x="116" y="70" width="38" height="70" rx="3" fill="var(--primary)" opacity="0.7"/>
      <rect x="162" y="60" width="40" height="80" rx="3" fill="var(--primary-dark, #047857)" opacity="0.85"/>
      <g fill="rgba(255,255,255,0.6)">
        <rect x="26" y="90" width="6" height="8"/><rect x="40" y="90" width="6" height="8"/>
        <rect x="26" y="105" width="6" height="8"/><rect x="40" y="105" width="6" height="8"/>
        <rect x="74" y="62" width="6" height="8"/><rect x="88" y="62" width="6" height="8"/>
        <rect x="74" y="82" width="6" height="8"/><rect x="88" y="82" width="6" height="8"/>
        <rect x="74" y="102" width="6" height="8"/><rect x="88" y="102" width="6" height="8"/>
      </g>
      <circle cx="180" cy="30" r="10" fill="#fbbf24"/>
    </svg>`,
  };
  return `<div class="empty-state">
    ${svgs[kind] || ""}
    <h3>${title}</h3>
    <p>${body}</p>
  </div>`;
}

// Wrapper que adapta a util pra receber o objeto de ocorrência inteiro.
function fallbackImage(o) {
  return fallbackImageUtil(o.occId || o.occTitle);
}

// ------------------------- Modal de criação --------------------------------

const modal     = document.getElementById("modal-bg");
const formNew   = document.getElementById("form-new");
const btnCancel = document.getElementById("btn-cancel");
const btnSave   = document.getElementById("btn-save");
const selectCat = document.getElementById("oc-category");

let currentCoords = null;
let createMap = null;
let createMarker = null;
const coordsHint = document.getElementById("oc-coords-hint");

function setCreateCoords(lat, lng, src = "") {
  currentCoords = { lat, lng };
  if (coordsHint) {
    coordsHint.innerHTML = `📍 <b>${lat.toFixed(5)}, ${lng.toFixed(5)}</b> ${src ? `· ${src}` : ""}`;
    coordsHint.classList.add("ok");
  }
  if (createMap && createMarker) {
    createMarker.setLatLng([lat, lng]);
    createMap.setView([lat, lng], 16);
  }
}

function initCreateMap() {
  if (createMap) return;
  const mapDiv = document.getElementById("oc-map");
  if (!mapDiv) return;
  const start = currentCoords || { lat: -23.55, lng: -46.63 };
  createMap = L.map(mapDiv, { zoomControl: true, attributionControl: false })
    .setView([start.lat, start.lng], currentCoords ? 16 : 12);
  L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
    maxZoom: 19, subdomains: "abcd", crossOrigin: true,
  }).addTo(createMap);
  createMarker = L.marker([start.lat, start.lng], { draggable: true }).addTo(createMap);
  createMarker.on("dragend", () => {
    const { lat, lng } = createMarker.getLatLng();
    setCreateCoords(lat, lng, "ajustado manualmente");
  });
  createMap.on("click", (e) => {
    setCreateCoords(e.latlng.lat, e.latlng.lng, "via clique no mapa");
  });
  // botão minha-localização
  const locBtn = document.getElementById("oc-locate");
  if (locBtn) {
    locBtn.addEventListener("click", () => {
      if (!navigator.geolocation) { toast("geolocalização indisponível", "error"); return; }
      locBtn.classList.add("loading");
      navigator.geolocation.getCurrentPosition(
        pos => {
          locBtn.classList.remove("loading");
          setCreateCoords(pos.coords.latitude, pos.coords.longitude, "GPS");
        },
        () => {
          locBtn.classList.remove("loading");
          toast("permissão de localização negada", "error");
        },
        { timeout: 6000, enableHighAccuracy: true }
      );
    });
  }
  // ajusta tamanho após o modal abrir (display:none -> flex)
  requestAnimationFrame(() => createMap.invalidateSize());
}

fabNew.addEventListener("click", async () => {
  if (!isLogged) { window.location.href = "login.html"; return; }
  modal.classList.add("open");
  if (selectCat.options.length === 0) {
    try {
      const cats = await Api.listCategories();
      cats.forEach(c => {
        const opt = document.createElement("option");
        opt.value = c.categoryId;
        opt.textContent = c.categoryName;
        selectCat.appendChild(opt);
      });
    } catch (e) {
      toast("erro ao carregar categorias", "error");
    }
  }
  if (navigator.geolocation && !currentCoords) {
    navigator.geolocation.getCurrentPosition(
      pos => setCreateCoords(pos.coords.latitude, pos.coords.longitude, "GPS"),
      ()  => {},
      { timeout: 4000 }
    );
  }
  // inicializa o mini-mapa de criação (1x só)
  setTimeout(initCreateMap, 50);
});
// auto-completa cidade/UF do CEP no modal de nova ocorrência (via ViaCEP)
attachCepLookup(
  document.getElementById("oc-cep"),
  document.getElementById("oc-cep-hint")
);

// upload de foto via Cloudinary se as meta tags estiverem preenchidas;
// caso contrário deixa a URL manual como única opção
const uploaderActive = attachUploader({
  dropZone: document.getElementById("oc-drop"),
  fileInput: document.getElementById("oc-file"),
  preview:  document.getElementById("oc-preview"),
  urlInput: document.getElementById("oc-photo"),
  status:   document.getElementById("oc-upload-status"),
});
if (!uploaderActive) {
  // sem Cloudinary: esconde o upload zone e abre o fallback de URL
  const drop = document.getElementById("oc-drop");
  const fb   = document.querySelector(".upload-fallback");
  const urlI = document.getElementById("oc-photo");
  if (drop) drop.style.display = "none";
  if (fb)   { fb.open = true; fb.querySelector("summary").style.display = "none"; }
  if (urlI) urlI.required = true;
}

btnCancel.addEventListener("click", () => modal.classList.remove("open"));
modal.addEventListener("click", (e) => { if (e.target === modal) modal.classList.remove("open"); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape") modal.classList.remove("open"); });

formNew.addEventListener("submit", async (e) => {
  e.preventDefault();
  btnSave.disabled = true;
  btnSave.innerHTML = `<span class="spinner"></span> Publicando…`;
  const cep = document.getElementById("oc-cep").value.replace(/\D/g, "");
  const payload = {
    categoryId:  Number(selectCat.value),
    title:       document.getElementById("oc-title").value.trim(),
    description: document.getElementById("oc-desc").value.trim(),
    photoUrl:    document.getElementById("oc-photo").value.trim(),
    latitude:    currentCoords ? currentCoords.lat : null,
    longitude:   currentCoords ? currentCoords.lng : null,
    cep:         cep || null,
  };
  try {
    await Api.createOccurrence(payload, Auth.token());
    toast("Ocorrência publicada!", "success");
    modal.classList.remove("open");
    formNew.reset();
    loadFeed();
  } catch (err) {
    if (err.status === 401) { Auth.logout(); window.location.href = "login.html"; return; }
    toast(err.message || "erro ao publicar", "error");
  } finally {
    btnSave.disabled = false;
    btnSave.textContent = "Publicar";
  }
});

loadFeed();

// Onboarding na 1ª visita (após o feed começar a carregar)
setTimeout(() => startOnboarding(false), 600);

// Atalhos de teclado
mountKeyboardShortcuts({
  onNew: () => {
    if (!isLogged) { window.location.href = "login.html"; return; }
    document.getElementById("modal-bg")?.classList.add("open");
  },
  onSearch: () => {
    const s = document.getElementById("search");
    s?.focus();
    s?.select();
  },
  onEsc: () => {
    document.getElementById("modal-bg")?.classList.remove("open");
  },
});
