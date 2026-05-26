import { Api } from "./api.js";
import { Auth, toast } from "./auth.js";
import { Theme } from "./theme.js";
import { attachCepLookup } from "./cep.js";
import { attachUploader, cloudinaryConfigured } from "./upload.js";

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

function cardWithDistance(r) {
  const o = r.nearOcc;
  const loc = o.occCity ? `${escapeHtml(o.occCity)}${o.occUf ? "/" + escapeHtml(o.occUf) : ""}` : "—";
  return `
    <article class="card" data-id="${o.occId}">
      ${o.occPhotoUrl ? `<img class="card-img" src="${escapeAttr(o.occPhotoUrl)}" alt="" loading="lazy" decoding="async" onerror="this.style.display='none'" />` : ""}
      <div class="card-body">
        <div class="card-loc">
          <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
          ${loc} · <b style="color:var(--accent);">${r.nearDistance.toFixed(2)} km</b>
        </div>
        <h3>${escapeHtml(o.occTitle)}</h3>
        <p>${escapeHtml(o.occDescription)}</p>
        <div class="meta">
          <span class="badge ${o.occStatus}">${labelStatus(o.occStatus)}</span>
          <span class="vote-pill">${o.occVoteCount}</span>
        </div>
      </div>
    </article>`;
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

function statusColor(s) {
  return s === "resolved" ? "#0f9d58"
       : s === "in_progress" ? "#3b82f6"
       : "#f59e0b";
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

async function loadFeed() {
  feedEl.innerHTML = `<div class="skeleton skeleton-card"></div><div class="skeleton skeleton-card"></div>`;
  try {
    allOccs = await Api.listOccurrences();
    applyFilter();
  } catch (e) {
    feedEl.innerHTML = `<div class="empty">erro ao carregar: ${escapeHtml(e.message)}</div>`;
  }
}

function applyFilter() {
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
      ? `<div class="empty">nada encontrado pra esse filtro</div>`
      : `<div class="empty">Nenhuma ocorrência ainda${isLogged ? '.<br>Clique no <b>+</b> pra criar a primeira.' : '.<br><a href="login.html">Entre</a> pra reportar.'}</div>`;
    scheduleMarkerDraw([]);
    return;
  }

  // renderiza usando DocumentFragment pra reduzir reflows
  const tpl = document.createElement("template");
  tpl.innerHTML = filtered.map(cardHtml).join("");
  feedEl.replaceChildren(tpl.content);

  // delegação de evento pra cliques no feed (1 listener em vez de N)
  scheduleMarkerDraw(filtered);
}

feedEl.addEventListener("click", (e) => {
  const card = e.target.closest(".card");
  if (card && card.dataset.id) window.location.href = `occurrence.html?id=${card.dataset.id}`;
});

let searchTimer;
searchInput.addEventListener("input", () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(applyFilter, 180);
});

// chips de filtro de status
if (chipsEl) {
  chipsEl.addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-status]");
    if (!btn) return;
    activeStatus = btn.dataset.status;
    chipsEl.querySelectorAll("button").forEach(b => b.classList.toggle("active", b === btn));
    applyFilter();
  });
}

function cardHtml(o) {
  const loc = o.occCity ? `${escapeHtml(o.occCity)}${o.occUf ? "/" + escapeHtml(o.occUf) : ""}` : "—";
  return `
    <article class="card" data-id="${o.occId}">
      ${o.occPhotoUrl ? `<img class="card-img" src="${escapeAttr(o.occPhotoUrl)}" alt="" loading="lazy" decoding="async" onerror="this.style.display='none'" />` : ""}
      <div class="card-body">
        <div class="card-loc">
          <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
          ${loc}
        </div>
        <h3>${escapeHtml(o.occTitle)}</h3>
        <p>${escapeHtml(o.occDescription)}</p>
        <div class="meta">
          <span class="badge ${o.occStatus}">${labelStatus(o.occStatus)}</span>
          <span class="vote-pill">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg>
            ${o.occVoteCount}
          </span>
        </div>
      </div>
    </article>`;
}
function labelStatus(s) {
  return ({ open: "Aberto", in_progress: "Em andamento", resolved: "Resolvido" }[s] || s);
}

// ------------------------- Modal de criação --------------------------------

const modal     = document.getElementById("modal-bg");
const formNew   = document.getElementById("form-new");
const btnCancel = document.getElementById("btn-cancel");
const btnSave   = document.getElementById("btn-save");
const selectCat = document.getElementById("oc-category");

let currentCoords = null;
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
  if (navigator.geolocation) {
    navigator.geolocation.getCurrentPosition(
      pos => { currentCoords = { lat: pos.coords.latitude, lng: pos.coords.longitude }; },
      ()  => { currentCoords = null; },
      { timeout: 4000 }
    );
  }
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

function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, ch => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  }[ch]));
}
function escapeAttr(s) { return escapeHtml(s); }

loadFeed();
