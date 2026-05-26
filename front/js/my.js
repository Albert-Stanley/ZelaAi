import { Api } from "./api.js";
import { Auth, toast } from "./auth.js";
import { Theme } from "./theme.js";

Theme.mountToggle(document.querySelector(".header-actions"));

Auth.requireAuth();

const user = Auth.user();
document.getElementById("user-tag").textContent = `@${user.userUsername}`;
document.getElementById("logout-link").addEventListener("click", (e) => {
  e.preventDefault();
  Auth.logout();
  window.location.replace("login.html");
});

const listEl = document.getElementById("list");
let cache = [];

async function load() {
  try {
    cache = await Api.myOccurrences(Auth.token());
    render();
  } catch (e) {
    if (e.status === 401) { Auth.logout(); window.location.replace("login.html"); return; }
    listEl.innerHTML = `<div class="empty">erro: ${escapeHtml(e.message)}</div>`;
  }
}

function render() {
  if (cache.length === 0) {
    listEl.innerHTML = `<div class="empty">Você ainda não criou nenhuma ocorrência.<br>Volte ao <a href="index.html">feed</a> e clique no <b>+</b>.</div>`;
    return;
  }
  listEl.innerHTML = cache.map(cardHtml).join("");
}

// delegação: navega ao detalhe, OU executa edit/delete dependendo do click
listEl.addEventListener("click", async (e) => {
  const actionBtn = e.target.closest("button[data-act]");
  if (actionBtn) {
    e.stopPropagation();
    const id = Number(actionBtn.closest("[data-id]").dataset.id);
    const act = actionBtn.dataset.act;
    if (act === "edit") return openEditModal(id);
    if (act === "delete") return askDelete(id);
    return;
  }
  const card = e.target.closest(".card");
  if (card && card.dataset.id) window.location.href = `occurrence.html?id=${card.dataset.id}`;
});

async function askDelete(id) {
  const o = cache.find(x => x.occId === id);
  if (!o) return;
  if (!confirm(`Excluir "${o.occTitle}"?\n\nEla ficará oculta do feed (soft delete).`)) return;
  try {
    await Api.deleteOccurrence(id, Auth.token());
    cache = cache.filter(x => x.occId !== id);
    render();
    toast("ocorrência excluída", "success");
  } catch (e) {
    toast(e.message || "erro ao excluir", "error");
  }
}

// ---------- modal de edição (criado on-demand) ----------
function openEditModal(id) {
  const o = cache.find(x => x.occId === id);
  if (!o) return;
  let modal = document.getElementById("edit-modal");
  if (!modal) {
    modal = document.createElement("div");
    modal.id = "edit-modal";
    modal.className = "modal-bg";
    modal.innerHTML = `
      <div class="modal">
        <h2>Editar ocorrência</h2>
        <p class="modal-sub">Atualize título, descrição ou foto.</p>
        <form id="edit-form">
          <div class="field">
            <label for="ed-title">Título</label>
            <input id="ed-title" type="text" required maxlength="150" />
          </div>
          <div class="field">
            <label for="ed-desc">Descrição</label>
            <textarea id="ed-desc" required maxlength="2000"></textarea>
          </div>
          <div class="field">
            <label for="ed-photo">URL da foto</label>
            <input id="ed-photo" type="url" />
          </div>
          <div class="actions">
            <button type="button" class="btn secondary" data-act="cancel">Cancelar</button>
            <button type="submit" class="btn" id="ed-save">Salvar</button>
          </div>
        </form>
      </div>
    `;
    document.body.appendChild(modal);
    modal.addEventListener("click", (e) => {
      if (e.target === modal || e.target.closest("[data-act='cancel']"))
        modal.classList.remove("open");
    });
    modal.querySelector("#edit-form").addEventListener("submit", onEditSubmit);
  }
  modal.dataset.id = id;
  modal.querySelector("#ed-title").value = o.occTitle;
  modal.querySelector("#ed-desc").value  = o.occDescription;
  modal.querySelector("#ed-photo").value = o.occPhotoUrl || "";
  modal.classList.add("open");
}

async function onEditSubmit(e) {
  e.preventDefault();
  const modal = document.getElementById("edit-modal");
  const id = Number(modal.dataset.id);
  const btn = modal.querySelector("#ed-save");
  btn.disabled = true;
  btn.innerHTML = `<span class="spinner"></span> salvando…`;
  const patch = {
    upTitle:       modal.querySelector("#ed-title").value.trim(),
    upDescription: modal.querySelector("#ed-desc").value.trim(),
    upPhotoUrl:    modal.querySelector("#ed-photo").value.trim() || null,
  };
  try {
    const updated = await Api.updateOccurrence(id, patch, Auth.token());
    cache = cache.map(o => o.occId === id ? updated : o);
    render();
    modal.classList.remove("open");
    toast("ocorrência atualizada", "success");
  } catch (err) {
    toast(err.message || "erro ao salvar", "error");
  } finally {
    btn.disabled = false;
    btn.textContent = "Salvar";
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
        <div class="card-actions">
          <button type="button" class="btn ghost small" data-act="edit">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
            Editar
          </button>
          <button type="button" class="btn ghost small" data-act="delete" style="color:var(--danger);">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-2 14a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2L5 6"/></svg>
            Excluir
          </button>
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
