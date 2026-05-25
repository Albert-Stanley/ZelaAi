import { Api } from "./api.js";
import { Auth, toast } from "./auth.js";

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
  window.location.replace("login.html");
});

const params = new URLSearchParams(window.location.search);
const occId = Number(params.get("id"));
const contentEl = document.getElementById("content");

if (!occId) {
  contentEl.innerHTML = `<div class="empty">id inválido</div>`;
  throw new Error("no id");
}

async function load() {
  contentEl.innerHTML = `<div class="skeleton skeleton-card"></div>`;
  try {
    const o = await Api.getOccurrence(occId);
    render(o);
  } catch (e) {
    contentEl.innerHTML = `<div class="empty">erro: ${escapeHtml(e.message)}</div>`;
  }
}

function render(o) {
  const voteIcon = `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg>`;

  const actionBtns = isLogged
    ? `<button class="btn small" id="btn-vote" style="flex:1;">${voteIcon} Votar</button>
       <button class="btn small secondary" id="btn-unvote" style="flex:1;">Tirar voto</button>`
    : `<a class="btn small" href="login.html" style="flex:1;text-decoration:none;">Entrar para votar</a>`;

  const statusBtns = isLogged
    ? `<div class="action-bar-row">
         <div class="status-group">
           <button class="btn small ghost" data-st="open">Reabrir</button>
           <button class="btn small secondary" data-st="in_progress">Em andamento</button>
           <button class="btn small" data-st="resolved">Marcar resolvida</button>
         </div>
       </div>`
    : "";

  contentEl.innerHTML = `
    ${o.occPhotoUrl ? `<img class="detail-img" src="${escapeAttr(o.occPhotoUrl)}" alt="" onerror="this.style.display='none'" />` : ""}
    <span class="badge ${o.occStatus}">${labelStatus(o.occStatus)}</span>
    <h2 style="margin-top:8px;">${escapeHtml(o.occTitle)}</h2>
    <p class="desc">${escapeHtml(o.occDescription)}</p>

    <div class="info-grid">
      <div class="item">
        <span class="label">Cidade</span>
        <span class="value">${escapeHtml(o.occCity || "—")}${o.occUf ? " / " + escapeHtml(o.occUf) : ""}</span>
      </div>
      <div class="item">
        <span class="label">CEP</span>
        <span class="value">${escapeHtml(o.occCep || "—")}</span>
      </div>
      <div class="item">
        <span class="label">Categoria</span>
        <span class="value">#${o.occCategoryId}</span>
      </div>
      <div class="item">
        <span class="label">Mandato vinculado</span>
        <span class="value">${o.occMandateId ? "#" + o.occMandateId : "—"}</span>
      </div>
      <div class="item">
        <span class="label">Criada em</span>
        <span class="value">${fmtDate(o.occCreatedAt)}</span>
      </div>
      <div class="item">
        <span class="label">Resolvida em</span>
        <span class="value">${o.occResolvedAt ? fmtDate(o.occResolvedAt) : "—"}</span>
      </div>
    </div>

    <div class="action-bar">
      <div class="action-bar-row">
        <span class="vote-pill" id="vote-count">${voteIcon} ${o.occVoteCount}</span>
        ${actionBtns}
      </div>
      ${statusBtns}
    </div>
  `;

  if (isLogged) {
    document.getElementById("btn-vote").addEventListener("click", doVote);
    document.getElementById("btn-unvote").addEventListener("click", doUnvote);
    contentEl.querySelectorAll("[data-st]").forEach(btn => {
      btn.addEventListener("click", () => doStatus(btn.dataset.st));
    });
  }
}

async function doVote() {
  toggleBtns(true);
  try {
    const res = await Api.vote(occId, Auth.token());
    refreshVotePill(res.voteCount);
    toast("Voto computado!", "success");
  } catch (err) {
    if (err.status === 401) { Auth.logout(); window.location.replace("login.html"); return; }
    if (err.status === 409) toast("você já votou nessa", "error");
    else toast(err.message || "erro ao votar", "error");
  } finally { toggleBtns(false); }
}

async function doUnvote() {
  toggleBtns(true);
  try {
    const res = await Api.unvote(occId, Auth.token());
    refreshVotePill(res.voteCount);
    toast("Voto removido.");
  } catch (err) {
    if (err.status === 401) { Auth.logout(); window.location.replace("login.html"); return; }
    if (err.status === 404) toast("você não tinha votado", "error");
    else toast(err.message || "erro ao remover voto", "error");
  } finally { toggleBtns(false); }
}

async function doStatus(st) {
  try {
    await Api.updateStatus(occId, st, Auth.token());
    toast(`Status alterado para: ${labelStatus(st)}`, "success");
    load();
  } catch (err) {
    if (err.status === 401) { Auth.logout(); window.location.replace("login.html"); return; }
    toast(err.message || "erro ao alterar status", "error");
  }
}

function refreshVotePill(count) {
  const el = document.getElementById("vote-count");
  if (!el) return;
  const voteIcon = `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg>`;
  el.innerHTML = `${voteIcon} ${count}`;
}

function toggleBtns(disabled) {
  const a = document.getElementById("btn-vote");
  const b = document.getElementById("btn-unvote");
  if (a) a.disabled = disabled;
  if (b) b.disabled = disabled;
}

function fmtDate(iso) {
  try { return new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }); } catch { return iso; }
}
function labelStatus(s) {
  return ({ open: "Aberto", in_progress: "Em andamento", resolved: "Resolvido" }[s] || s);
}
function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, ch => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  }[ch]));
}
function escapeAttr(s) { return escapeHtml(s); }

load();
