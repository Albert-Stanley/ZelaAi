import { Api } from "./api.js";
import { Auth } from "./auth.js";

Auth.requireAuth();

const user = Auth.user();
document.getElementById("user-tag").textContent = `@${user.userUsername}`;
document.getElementById("logout-link").addEventListener("click", (e) => {
  e.preventDefault();
  Auth.logout();
  window.location.replace("login.html");
});

const listEl = document.getElementById("list");

async function load() {
  try {
    const occs = await Api.myOccurrences(Auth.token());
    if (occs.length === 0) {
      listEl.innerHTML = `<div class="empty">Você ainda não criou nenhuma ocorrência.<br>Volte ao <a href="index.html">feed</a> e clique no <b>+</b>.</div>`;
      return;
    }
    listEl.innerHTML = occs.map(cardHtml).join("");
    listEl.querySelectorAll(".card").forEach(card => {
      card.addEventListener("click", () => {
        window.location.href = `occurrence.html?id=${card.dataset.id}`;
      });
    });
  } catch (e) {
    if (e.status === 401) { Auth.logout(); window.location.replace("login.html"); return; }
    listEl.innerHTML = `<div class="empty">erro: ${escapeHtml(e.message)}</div>`;
  }
}

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
function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, ch => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  }[ch]));
}
function escapeAttr(s) { return escapeHtml(s); }

load();
