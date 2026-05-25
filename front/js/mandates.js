import { Api } from "./api.js";
import { Auth } from "./auth.js";
import { Theme } from "./theme.js";

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

const listEl = document.getElementById("list");

async function load() {
  try {
    const mandates = await Api.listMandates();
    if (mandates.length === 0) {
      listEl.innerHTML = `<div class="empty">Nenhum mandato cadastrado.<br>Crie via <code>POST /mandates</code> no Insomnia ou rode <code>./seed-demo.sh</code>.</div>`;
      return;
    }
    listEl.innerHTML = mandates.map(mandCardHtml).join("");
    mandates.forEach(loadScore);
  } catch (e) {
    listEl.innerHTML = `<div class="empty">erro: ${escapeHtml(e.message)}</div>`;
  }
}

function mandCardHtml(m) {
  const pol = m.mandatePolitician;
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

async function loadScore(m) {
  const target = document.getElementById(`score-${m.mandateId}`);
  if (!target) return;
  try {
    const s = await Api.getMandateScore(m.mandateId);
    target.innerHTML = renderScore(s);
  } catch (e) {
    target.innerHTML = `<div class="empty">erro ao carregar score: ${escapeHtml(e.message)}</div>`;
  }
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

function fmtDate(iso) {
  try {
    const d = new Date(iso);
    return d.toLocaleDateString("pt-BR", { month: "short", year: "numeric" });
  } catch { return iso; }
}

function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, ch => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  }[ch]));
}

load();
