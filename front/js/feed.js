import { Api } from "./api.js";
import { Auth, toast } from "./auth.js";

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

// ------------------------------- Mapa --------------------------------------

const map = L.map("map", { zoomControl: true, attributionControl: false })
  .setView([-23.55, -46.63], 12);
L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
  attribution: "© OpenStreetMap, © CARTO",
  maxZoom: 19,
  subdomains: "abcd",
}).addTo(map);
L.control.attribution({ prefix: false, position: "bottomright" })
  .addAttribution("© OSM · CARTO").addTo(map);
setTimeout(() => map.invalidateSize(), 200);

let markers = [];
function drawMarkers(occs) {
  markers.forEach(m => map.removeLayer(m));
  markers = [];
  const bounds = [];
  occs.forEach((o) => {
    if (o.occLatitude == null || o.occLongitude == null) return;
    const m = L.marker([o.occLatitude, o.occLongitude]).addTo(map);
    m.bindPopup(
      `<b>${escapeHtml(o.occTitle)}</b><br>` +
      `<small>${o.occVoteCount} voto(s) · ${labelStatus(o.occStatus)}</small><br>` +
      `<a href="occurrence.html?id=${o.occId}">ver detalhes →</a>`
    );
    markers.push(m);
    bounds.push([o.occLatitude, o.occLongitude]);
  });
  if (bounds.length === 1) map.setView(bounds[0], 14);
  else if (bounds.length > 1) map.fitBounds(bounds, { padding: [30, 30] });
}

// ---------------------------- Feed (cards) ---------------------------------

const feedEl  = document.getElementById("feed");
const countEl = document.getElementById("count");
const searchInput = document.getElementById("search");

let allOccs = [];

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
  const filtered = q
    ? allOccs.filter(o =>
        (o.occTitle       || "").toLowerCase().includes(q) ||
        (o.occDescription || "").toLowerCase().includes(q) ||
        (o.occCity        || "").toLowerCase().includes(q) ||
        (o.occCep         || "").includes(q)
      )
    : allOccs;

  countEl.textContent = q
    ? `${filtered.length} de ${allOccs.length}`
    : `${allOccs.length} ${allOccs.length === 1 ? "item" : "itens"}`;

  if (filtered.length === 0) {
    feedEl.innerHTML = q
      ? `<div class="empty">nada encontrado pra "${escapeHtml(q)}"</div>`
      : `<div class="empty">Nenhuma ocorrência ainda${isLogged ? '.<br>Clique no <b>+</b> pra criar a primeira.' : '.<br><a href="login.html">Entre</a> pra reportar.'}</div>`;
    drawMarkers([]);
    return;
  }
  feedEl.innerHTML = filtered.map(cardHtml).join("");
  feedEl.querySelectorAll(".card").forEach(card => {
    card.addEventListener("click", () => {
      window.location.href = `occurrence.html?id=${card.dataset.id}`;
    });
  });
  drawMarkers(filtered);
}

let searchTimer;
searchInput.addEventListener("input", () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(applyFilter, 150);
});

function cardHtml(o) {
  const loc = o.occCity ? `${escapeHtml(o.occCity)}${o.occUf ? "/" + escapeHtml(o.occUf) : ""}` : "—";
  return `
    <article class="card" data-id="${o.occId}">
      ${o.occPhotoUrl ? `<img class="card-img" src="${escapeAttr(o.occPhotoUrl)}" alt="" loading="lazy" onerror="this.style.display='none'" />` : ""}
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
btnCancel.addEventListener("click", () => modal.classList.remove("open"));
modal.addEventListener("click", (e) => { if (e.target === modal) modal.classList.remove("open"); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape") modal.classList.remove("open"); });

formNew.addEventListener("submit", async (e) => {
  e.preventDefault();
  btnSave.disabled = true;
  btnSave.innerHTML = `<span class="spinner"></span> Publicando…`;
  const cep = document.getElementById("oc-cep").value.trim();
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
