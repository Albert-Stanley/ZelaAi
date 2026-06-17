import { Api } from "./api.js";
import { Auth } from "./auth.js";
import { Theme } from "./theme.js";
import { escapeHtml } from "./util.js";

Theme.mountToggle(document.querySelector(".header-actions"));

const isLogged = Auth.isLogged();
const user = Auth.user();
const userTag = document.getElementById("user-tag");
const logoutLink = document.getElementById("logout-link");
const myLink = document.getElementById("my-link");

if (isLogged) {
  userTag.textContent = `@${user.userUsername}`;
  if (myLink) myLink.style.display = "";
} else {
  userTag.innerHTML = `<a href="login.html" style="color:white;text-decoration:underline;font-weight:600;">Entrar</a>`;
  logoutLink.style.display = "none";
  if (myLink) myLink.style.display = "none";
}
logoutLink.addEventListener("click", (e) => {
  e.preventDefault();
  Auth.logout();
  window.location.reload();
});

const listEl    = document.getElementById("list");
const emptyEl   = document.getElementById("list-empty");
const countEl   = document.getElementById("mandate-count");

// Estado dos filtros
let allMandates    = [];
let allScores      = {};
let searchQuery    = "";
let activeRole     = "all";
let activePeriod   = "all";

// ---------- Init ---------------------------------------------------------

async function load() {
  try {
    const mandates = await Api.listMandates();
    allMandates = mandates;
    if (mandates.length === 0) {
      listEl.innerHTML = `<div class="empty">Nenhum mandato cadastrado.<br>Crie via <code>POST /mandates</code> no Insomnia.</div>`;
      emptyEl.style.display = "none";
      renderRanking([]);
      renderGlobalStats([]);
      return;
    }
    // Renderiza cards como skeleton, depois carrega scores em paralelo
    renderList(mandates);
    const scoreResults = await Promise.allSettled(mandates.map(m => Api.getMandateScore(m.mandateId)));
    scoreResults.forEach((r, i) => {
      const m = mandates[i];
      if (r.status === "fulfilled") {
        allScores[m.mandateId] = r.value;
        const el = document.getElementById(`score-${m.mandateId}`);
        if (el) el.innerHTML = renderScore(r.value);
      }
    });
    renderRanking(mandates);
    renderGlobalStats(mandates);
    applyFilters();
  } catch (e) {
    listEl.innerHTML = `<div class="empty">erro: ${escapeHtml(e.message)}</div>`;
  }
}

// ---------- Filter -------------------------------------------------------

function applyFilters() {
  const q = searchQuery.toLowerCase();
  const now = new Date();

  const filtered = allMandates.filter(m => {
    const pol = m.mandatePolitician;
    // search
    if (q) {
      const haystack = [
        pol.politicianName,
        pol.politicianParty,
        pol.politicianRole,
        m.mandateCity,
        m.mandateUf,
      ].join(" ").toLowerCase();
      if (!haystack.includes(q)) return false;
    }
    // role filter
    if (activeRole !== "all" && !pol.politicianRole.toLowerCase().includes(activeRole.toLowerCase())) return false;
    // period filter
    if (activePeriod === "active") {
      if (new Date(m.mandateEndDate) < now) return false;
    } else if (activePeriod === "past") {
      if (new Date(m.mandateEndDate) >= now) return false;
    }
    return true;
  });

  // Sort by score desc
  filtered.sort((a, b) => {
    const sa = allScores[a.mandateId]?.scoreResolvedPct ?? -1;
    const sb = allScores[b.mandateId]?.scoreResolvedPct ?? -1;
    return sb - sa;
  });

  if (countEl) countEl.textContent = `${filtered.length} gestão${filtered.length !== 1 ? "ões" : ""}`;

  if (filtered.length === 0) {
    listEl.innerHTML = "";
    if (emptyEl) emptyEl.style.display = "";
  } else {
    if (emptyEl) emptyEl.style.display = "none";
    renderList(filtered);
    // Repopulate scores from cache
    filtered.forEach(m => {
      const el = document.getElementById(`score-${m.mandateId}`);
      if (el && allScores[m.mandateId]) el.innerHTML = renderScore(allScores[m.mandateId]);
    });
  }
}

function renderList(mandates) {
  listEl.innerHTML = mandates.map(mandCardHtml).join("");
}

// ---------- Render -------------------------------------------------------

function mandCardHtml(m) {
  const pol = m.mandatePolitician;
  const now = new Date();
  const isActive = new Date(m.mandateEndDate) >= now;
  return `
    <article class="mandate-card" data-id="${m.mandateId}">
      <div class="mc-head">
        <div>
          <div class="mc-name">${escapeHtml(pol.politicianName)}</div>
          <div class="mc-meta">
            <span class="badge" style="background:var(--info-soft);color:#1e40af;border-color:#bfdbfe;">${escapeHtml(pol.politicianRole)}</span>
            <span>${escapeHtml(pol.politicianParty)}</span>
            <span>·</span>
            <span>${escapeHtml(m.mandateCity || "—")}${m.mandateUf ? "/" + escapeHtml(m.mandateUf) : ""}</span>
            ${isActive ? `<span class="badge resolved" style="font-size:0.65rem;padding:2px 6px;">Vigente</span>` : `<span class="badge open" style="font-size:0.65rem;padding:2px 6px;">Encerrado</span>`}
          </div>
        </div>
        <div class="mc-period">${fmtDate(m.mandateStartDate)}<br>— ${fmtDate(m.mandateEndDate)}</div>
      </div>
      <div class="mc-score" id="score-${m.mandateId}">
        <div class="loading"><span class="spinner"></span> calculando score…</div>
      </div>
    </article>
  `;
}

function renderScore(s) {
  const pct = Math.round(s.scoreResolvedPct);
  const tempColor =
    pct >= 75 ? "linear-gradient(90deg, #16a34a, #22d3a0)" :
    pct >= 50 ? "linear-gradient(90deg, #65a30d, #84cc16)" :
    pct >= 25 ? "linear-gradient(90deg, #f59e0b, #fbbf24)" :
                "linear-gradient(90deg, #dc2626, #ef4444)";
  const textColor =
    pct >= 75 ? "#0a7c45" :
    pct >= 50 ? "#4d7c0f" :
    pct >= 25 ? "#b45309" :
                "#b91c1c";
  const tempLabel =
    pct >= 75 ? "Excelente gestão" :
    pct >= 50 ? "Boa gestão" :
    pct >= 25 ? "Gestão mediana" :
    s.scoreTotal === 0 ? "Sem dados ainda" : "Gestão precária";

  return `
    <div class="score-grid">
      <div class="score-stat">
        <div class="score-stat-label">Reportadas</div>
        <div class="score-stat-value">${s.scoreTotal}</div>
      </div>
      <div class="score-stat">
        <div class="score-stat-label">Resolvidas</div>
        <div class="score-stat-value">${s.scoreResolved}</div>
      </div>
      <div class="score-stat">
        <div class="score-stat-label">Votos</div>
        <div class="score-stat-value">${s.scoreTotalVotes}</div>
      </div>
      <div class="score-stat">
        <div class="score-stat-label">Tempo médio</div>
        <div class="score-stat-value">${s.scoreAvgDaysToFix.toFixed(1)}d</div>
      </div>
    </div>
    <div class="thermometer">
      <div class="thermometer-fill" style="width:${pct}%;background:${tempColor};"></div>
    </div>
    <div class="thermometer-label" style="color:${textColor};">
      ${pct}% resolvido · ${tempLabel}
    </div>
  `;
}

function renderRanking(mandates) {
  const el = document.getElementById("mandate-ranking");
  if (!el) return;
  const sorted = [...mandates].sort((a, b) => {
    const sa = allScores[a.mandateId]?.scoreResolvedPct ?? -1;
    const sb = allScores[b.mandateId]?.scoreResolvedPct ?? -1;
    return sb - sa;
  });
  const top = sorted.slice(0, 5);
  if (top.length === 0) {
    el.innerHTML = `<h4 class="sidebar-title">Ranking</h4><div class="sidebar-loading">sem dados</div>`;
    return;
  }
  el.innerHTML = `
    <h4 class="sidebar-title">Top gestões</h4>
    <ol class="sidebar-ranking">
      ${top.map((m, i) => {
        const s = allScores[m.mandateId];
        const pct = s ? Math.round(s.scoreResolvedPct) : "?";
        const pol = m.mandatePolitician;
        const color = pct >= 75 ? "var(--primary)" : pct >= 50 ? "#65a30d" : pct >= 25 ? "#f59e0b" : "#dc2626";
        return `
          <li class="sidebar-ranking-item">
            <span class="sidebar-rank-num">${i+1}</span>
            <div class="sidebar-rank-info">
              <strong>${escapeHtml(pol.politicianName)}</strong>
              <small>${escapeHtml(m.mandateCity || pol.politicianParty)}</small>
            </div>
            <span class="sidebar-rank-score" style="color:${color};">${pct}%</span>
          </li>`;
      }).join("")}
    </ol>
  `;
}

function renderGlobalStats(mandates) {
  const el = document.getElementById("mandate-global-stats");
  if (!el) return;
  const total = mandates.length;
  const now = new Date();
  const active = mandates.filter(m => new Date(m.mandateEndDate) >= now).length;
  const totalOcc = Object.values(allScores).reduce((s, sc) => s + sc.scoreTotal, 0);
  const totalRes = Object.values(allScores).reduce((s, sc) => s + sc.scoreResolved, 0);
  const globalPct = totalOcc > 0 ? Math.round(totalRes / totalOcc * 100) : 0;

  el.innerHTML = `
    <h4 class="sidebar-title">Estatísticas</h4>
    <div class="sidebar-stats-list">
      <div class="sidebar-stat-row"><span>Mandatos</span><strong>${total}</strong></div>
      <div class="sidebar-stat-row"><span>Vigentes</span><strong>${active}</strong></div>
      <div class="sidebar-stat-row"><span>Ocorrências</span><strong>${totalOcc}</strong></div>
      <div class="sidebar-stat-row"><span>Resolvidas</span><strong>${totalRes}</strong></div>
      <div class="sidebar-stat-row"><span>Taxa global</span><strong style="color:var(--primary);">${globalPct}%</strong></div>
    </div>
  `;
}

// ---------- Event listeners ----------------------------------------------

// Busca desktop
const searchDesk = document.getElementById("mandate-search");
if (searchDesk) {
  searchDesk.addEventListener("input", () => {
    searchQuery = searchDesk.value.trim();
    const mob = document.getElementById("mandate-search-mobile");
    if (mob) mob.value = searchQuery;
    applyFilters();
  });
}

// Busca mobile
const searchMob = document.getElementById("mandate-search-mobile");
if (searchMob) {
  searchMob.addEventListener("input", () => {
    searchQuery = searchMob.value.trim();
    const desk = document.getElementById("mandate-search");
    if (desk) desk.value = searchQuery;
    applyFilters();
  });
}

// Filtro de cargo
document.getElementById("role-filter")?.querySelectorAll("button").forEach(btn => {
  btn.addEventListener("click", () => {
    document.getElementById("role-filter").querySelectorAll("button").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    activeRole = btn.dataset.role;
    applyFilters();
  });
});

// Filtro de período
document.getElementById("period-filter")?.querySelectorAll("button").forEach(btn => {
  btn.addEventListener("click", () => {
    document.getElementById("period-filter").querySelectorAll("button").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    activePeriod = btn.dataset.period;
    applyFilters();
  });
});

// ---------- Helpers ------------------------------------------------------

function fmtDate(iso) {
  try {
    return new Date(iso).toLocaleDateString("pt-BR", { month: "short", year: "numeric" });
  } catch { return iso; }
}

load();
