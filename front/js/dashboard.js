// =============================================================================
// ZelaAi — Dashboard: agrega dados de /occurrences, /categories e /mandates
// e renderiza KPIs + gráficos (Chart.js) + listas top-N.
// Reativo ao theme toggle.
// =============================================================================

import { Api } from "./api.js";
import { Auth } from "./auth.js";
import { Theme } from "./theme.js";
import { escapeHtml, labelStatus } from "./util.js";

const isLogged = Auth.isLogged();
const user     = Auth.user();
const userTag    = document.getElementById("user-tag");
const logoutLink = document.getElementById("logout-link");
const myLink     = document.getElementById("my-link");

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

Theme.mountToggle(document.querySelector(".header-actions"));

// --------------------------- Paleta dinâmica -------------------------------

const palette = () => {
  const cs = getComputedStyle(document.documentElement);
  return {
    text:    cs.getPropertyValue("--text").trim(),
    soft:    cs.getPropertyValue("--text-soft").trim(),
    muted:   cs.getPropertyValue("--text-muted").trim(),
    border:  cs.getPropertyValue("--border").trim(),
    primary: cs.getPropertyValue("--primary").trim(),
    accent:  cs.getPropertyValue("--accent").trim(),
    warn:    cs.getPropertyValue("--warn").trim(),
    info:    cs.getPropertyValue("--info").trim(),
    danger:  cs.getPropertyValue("--danger").trim(),
    surface: cs.getPropertyValue("--surface").trim(),
  };
};

const charts = {};

// --------------------------- Helpers ---------------------------------------

const labelStatus = s => ({ open: "Aberto", in_progress: "Em andamento", resolved: "Resolvido" }[s] || s);
const fmtMonth = (d) => d.toLocaleDateString("pt-BR", { month: "short", year: "2-digit" });

function groupBy(arr, keyFn) {
  const m = new Map();
  for (const it of arr) {
    const k = keyFn(it);
    m.set(k, (m.get(k) || 0) + 1);
  }
  return m;
}

// --------------------------- Renderizadores --------------------------------

function renderKpis(occs, mandates) {
  const total       = occs.length;
  const open        = occs.filter(o => o.occStatus === "open").length;
  const inProgress  = occs.filter(o => o.occStatus === "in_progress").length;
  const resolved    = occs.filter(o => o.occStatus === "resolved").length;
  const totalVotes  = occs.reduce((acc, o) => acc + (o.occVoteCount || 0), 0);
  const resolPct    = total ? Math.round((resolved / total) * 100) : 0;
  const cities      = new Set(occs.map(o => (o.occCity || "").toLowerCase()).filter(Boolean)).size;

  const kpiHtml = `
    <div class="kpi accent">
      <div class="kpi-label">📋 Ocorrências</div>
      <div class="kpi-value">${total}</div>
      <div class="kpi-sub">${cities} cidade(s) impactada(s)</div>
    </div>
    <div class="kpi success">
      <div class="kpi-label">✓ Resolvidas</div>
      <div class="kpi-value">${resolved}</div>
      <div class="kpi-sub"><span class="up">${resolPct}%</span> de resolução</div>
    </div>
    <div class="kpi info">
      <div class="kpi-label">⚙ Em andamento</div>
      <div class="kpi-value">${inProgress}</div>
      <div class="kpi-sub">${open} ainda em aberto</div>
    </div>
    <div class="kpi warn">
      <div class="kpi-label">👍 Votos totais</div>
      <div class="kpi-value">${totalVotes}</div>
      <div class="kpi-sub">${mandates.length} mandato(s) acompanhado(s)</div>
    </div>
  `;
  document.getElementById("kpis").innerHTML = kpiHtml;
}

function renderStatusChart(occs) {
  const p = palette();
  const open       = occs.filter(o => o.occStatus === "open").length;
  const inProgress = occs.filter(o => o.occStatus === "in_progress").length;
  const resolved   = occs.filter(o => o.occStatus === "resolved").length;

  if (charts.status) charts.status.destroy();
  charts.status = new Chart(document.getElementById("ch-status"), {
    type: "doughnut",
    data: {
      labels: ["Aberto", "Em andamento", "Resolvido"],
      datasets: [{
        data: [open, inProgress, resolved],
        backgroundColor: [p.warn, p.info, p.primary],
        borderColor: p.surface,
        borderWidth: 3,
        hoverOffset: 8,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      cutout: "62%",
      plugins: {
        legend: { position: "bottom", labels: { color: p.soft, font: { family: "Inter", size: 12 }, padding: 14, usePointStyle: true } },
        tooltip: { backgroundColor: p.text, titleColor: p.surface, bodyColor: p.surface, padding: 10, cornerRadius: 8 },
      },
    },
  });
}

function renderCategoryChart(occs) {
  const p = palette();
  const grouped = groupBy(occs, o => o.occCategory?.categoryName || "—");
  const sorted = [...grouped.entries()].sort((a,b) => b[1]-a[1]).slice(0, 7);

  if (charts.category) charts.category.destroy();
  charts.category = new Chart(document.getElementById("ch-category"), {
    type: "bar",
    data: {
      labels: sorted.map(([k]) => k),
      datasets: [{
        data: sorted.map(([,v]) => v),
        backgroundColor: sorted.map((_, i) => i === 0 ? p.text : p.text + "55"),
        borderRadius: 4,
        borderSkipped: false,
        barThickness: 16,
      }],
    },
    options: {
      indexAxis: "y",
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: { backgroundColor: p.text, titleColor: p.surface, bodyColor: p.surface, padding: 10, cornerRadius: 8 },
      },
      scales: {
        x: { grid: { color: p.border, drawBorder: false }, ticks: { color: p.muted, precision: 0 } },
        y: { grid: { display: false }, ticks: { color: p.soft, font: { size: 11 } } },
      },
    },
  });
}

function renderMonthChart(occs) {
  const p = palette();
  // últimos 6 meses (incluindo o atual)
  const now = new Date();
  const buckets = [];
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    buckets.push({ key: `${d.getFullYear()}-${d.getMonth()}`, date: d, total: 0, resolved: 0 });
  }
  const idx = new Map(buckets.map((b, i) => [b.key, i]));

  for (const o of occs) {
    const d = new Date(o.occCreatedAt);
    if (isNaN(d.getTime())) continue;
    const k = `${d.getFullYear()}-${d.getMonth()}`;
    const i = idx.get(k);
    if (i == null) continue;
    buckets[i].total += 1;
    if (o.occStatus === "resolved") buckets[i].resolved += 1;
  }

  if (charts.month) charts.month.destroy();
  charts.month = new Chart(document.getElementById("ch-month"), {
    type: "line",
    data: {
      labels: buckets.map(b => fmtMonth(b.date)),
      datasets: [
        {
          label: "Reportadas",
          data: buckets.map(b => b.total),
          borderColor: p.primary,
          backgroundColor: p.primary + "22",
          fill: true,
          tension: 0.35,
          borderWidth: 2.5,
          pointRadius: 4,
          pointHoverRadius: 7,
          pointBackgroundColor: p.primary,
        },
        {
          label: "Resolvidas",
          data: buckets.map(b => b.resolved),
          borderColor: p.accent,
          backgroundColor: "transparent",
          tension: 0.35,
          borderWidth: 2,
          borderDash: [6, 4],
          pointRadius: 3,
          pointHoverRadius: 6,
          pointBackgroundColor: p.accent,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { position: "bottom", labels: { color: p.soft, font: { family: "Inter", size: 12 }, padding: 14, usePointStyle: true } },
        tooltip: { backgroundColor: p.text, titleColor: p.surface, bodyColor: p.surface, padding: 10, cornerRadius: 8 },
      },
      scales: {
        x: { grid: { display: false }, ticks: { color: p.muted } },
        y: { grid: { color: p.border, drawBorder: false }, ticks: { color: p.muted, precision: 0 } },
      },
    },
  });
}

function renderResolutionChart(occs) {
  const p = palette();
  const total    = occs.length || 1;
  const open     = occs.filter(o => o.occStatus === "open").length;
  const inProg   = occs.filter(o => o.occStatus === "in_progress").length;
  const resolved = occs.filter(o => o.occStatus === "resolved").length;
  const pct = arr => Math.round((arr / total) * 100);

  if (charts.resolution) charts.resolution.destroy();
  charts.resolution = new Chart(document.getElementById("ch-resolution"), {
    type: "polarArea",
    data: {
      labels: [`Aberto · ${pct(open)}%`, `Em andamento · ${pct(inProg)}%`, `Resolvido · ${pct(resolved)}%`],
      datasets: [{
        data: [open, inProg, resolved],
        backgroundColor: [p.warn + "cc", p.info + "cc", p.primary + "cc"],
        borderColor: p.surface,
        borderWidth: 2,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { position: "bottom", labels: { color: p.soft, font: { family: "Inter", size: 11 }, padding: 12, usePointStyle: true } },
        tooltip: { backgroundColor: p.text, titleColor: p.surface, bodyColor: p.surface, padding: 10, cornerRadius: 8 },
      },
      scales: {
        r: {
          ticks: { display: false },
          grid: { color: p.border },
          angleLines: { color: p.border },
        },
      },
    },
  });
}

function renderTopCities(occs) {
  const grouped = groupBy(occs, o => {
    if (!o.occCity) return null;
    return `${o.occCity}${o.occUf ? "/" + o.occUf : ""}`;
  });
  grouped.delete(null);
  const sorted = [...grouped.entries()].sort((a,b) => b[1]-a[1]).slice(0, 5);
  const el = document.getElementById("top-cities");
  if (sorted.length === 0) { el.innerHTML = `<div class="empty-mini">Sem cidades cadastradas ainda.</div>`; return; }
  el.innerHTML = sorted.map(([city, count], i) => `
    <div class="top-item">
      <span class="top-rank ${rankClass(i)}">${i+1}</span>
      <div>
        <div class="top-title">${escapeHtml(city)}</div>
        <div class="top-sub">${count} ocorrência(s) reportada(s)</div>
      </div>
      <span class="top-count">${count}</span>
    </div>
  `).join("");
}

function renderTopVoted(occs) {
  const sorted = [...occs]
    .filter(o => (o.occVoteCount || 0) > 0)
    .sort((a,b) => (b.occVoteCount || 0) - (a.occVoteCount || 0))
    .slice(0, 5);
  const el = document.getElementById("top-voted");
  if (sorted.length === 0) {
    el.innerHTML = `<div class="empty-mini">Ainda sem votos. Seja o primeiro a apoiar uma ocorrência!</div>`;
    return;
  }
  el.innerHTML = sorted.map((o, i) => `
    <a class="top-item" href="occurrence.html?id=${o.occId}" style="text-decoration:none;color:inherit;">
      <span class="top-rank ${rankClass(i)}">${i+1}</span>
      <div>
        <div class="top-title">${escapeHtml(o.occTitle)}</div>
        <div class="top-sub">${labelStatus(o.occStatus)} · ${escapeHtml(o.occCity || "—")}</div>
      </div>
      <span class="top-count">${o.occVoteCount}</span>
    </a>
  `).join("");
}

function renderMandates(mandates) {
  const el = document.getElementById("top-mandates");
  if (!mandates || mandates.length === 0) {
    el.innerHTML = `<div class="empty-mini">Nenhum mandato cadastrado.<br>Veja em <a href="mandates.html">Gestões</a>.</div>`;
    return;
  }
  // mostra até 5
  const sorted = mandates.slice(0, 5);
  el.innerHTML = sorted.map((m, i) => {
    const pol = m.mandatePolitician || {};
    return `
      <a class="top-item" href="mandates.html" style="text-decoration:none;color:inherit;">
        <span class="top-rank ${rankClass(i)}">${i+1}</span>
        <div>
          <div class="top-title">${escapeHtml(pol.politicianName || "—")}</div>
          <div class="top-sub">${escapeHtml(pol.politicianRole || "—")} · ${escapeHtml(pol.politicianParty || "")} · ${escapeHtml(m.mandateCity || "")}${m.mandateUf ? "/" + escapeHtml(m.mandateUf) : ""}</div>
        </div>
        <span class="top-count">→</span>
      </a>
    `;
  }).join("");
}

function rankClass(i) { return i === 0 ? "gold" : i === 1 ? "silver" : i === 2 ? "bronze" : ""; }

// --------------------------- Boot ------------------------------------------

let lastOccs = [];
let lastMandates = [];

async function load() {
  try {
    const [occs, mandates] = await Promise.all([
      Api.listOccurrences(),
      Api.listMandates().catch(() => []),
    ]);
    lastOccs = occs;
    lastMandates = mandates;
    renderAll();
  } catch (e) {
    document.getElementById("kpis").innerHTML = `<div class="empty" style="grid-column:1/-1">erro: ${escapeHtml(e.message)}</div>`;
  }
}

function renderAll() {
  renderKpis(lastOccs, lastMandates);
  renderStatusChart(lastOccs);
  renderCategoryChart(lastOccs);
  renderMonthChart(lastOccs);
  renderResolutionChart(lastOccs);
  renderTopCities(lastOccs);
  renderTopVoted(lastOccs);
  renderMandates(lastMandates);
}

// re-renderiza os charts quando o tema muda (cores dependem do tema)
const themeObserver = new MutationObserver(() => {
  if (lastOccs.length || lastMandates.length) renderAll();
});
themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

load();
