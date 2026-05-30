import { Api } from "./api.js";
import { Auth, toast } from "./auth.js";
import { Theme } from "./theme.js";
import { mountKeyboardShortcuts } from "./keys.js";

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

  const photoUrl = o.occPhotoUrl || fallbackSvg(o.occId, o.occTitle);
  const createdFull = fmtDate(o.occCreatedAt);
  const createdAgo  = timeAgoLong(o.occCreatedAt);
  contentEl.innerHTML = `
    <img class="detail-img" src="${escapeAttr(photoUrl)}" alt="" data-zoom="${escapeAttr(o.occPhotoUrl ? o.occPhotoUrl : "")}" onerror="this.onerror=null;this.src='${escapeAttr(fallbackSvg(o.occId, o.occTitle))}'" />
    <span class="badge ${o.occStatus}">${labelStatus(o.occStatus)}</span>
    <h2 style="margin-top:8px;">${escapeHtml(o.occTitle)}</h2>
    <div class="detail-meta" title="${escapeAttr(createdFull)}">
      <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
      Publicado em <strong>${createdFull}</strong> · ${createdAgo}
    </div>
    <p class="desc">${escapeHtml(o.occDescription)}</p>

    <div class="info-grid">
      <div class="item">
        <span class="label">Cidade</span>
        <span class="value">${escapeHtml(o.occCity || "—")}${o.occUf ? " / " + escapeHtml(o.occUf) : ""}</span>
      </div>
      <div class="item">
        <span class="label">CEP</span>
        <span class="value">
          ${escapeHtml(o.occCep || "—")}
          ${o.occCep ? `<button type="button" class="copy-cep-btn" data-cep="${escapeAttr(o.occCep)}" aria-label="Copiar CEP" title="Copiar CEP">
            <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
          </button>` : ""}
        </span>
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

    <div class="share-bar">
      <button class="btn small ghost" id="btn-share">
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
        Compartilhar
      </button>
      <button class="btn small ghost" id="btn-copy-link">
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>
        Copiar link
      </button>
      <a class="btn small ghost" href="#comments">
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
        Comentários
      </a>
    </div>

    <!-- ====== Comentários ====== -->
    <section class="comments-section" id="comments">
      <div class="comments-header">
        <h3>Comentários</h3>
        <span class="count" id="cm-count">—</span>
      </div>

      ${isLogged ? `
        <form id="cm-form" class="comment-compose">
          <textarea id="cm-body" placeholder="Comentar como @${escapeHtml(user.userUsername)}…" required maxlength="1000"></textarea>
          <button type="submit" class="btn small" id="cm-submit">Publicar</button>
        </form>
      ` : `
        <div class="comment-login-prompt">
          <a href="login.html">Entre</a> para comentar.
        </div>
      `}

      <div class="comment-list" id="cm-list">
        <div class="empty-mini">carregando comentários…</div>
      </div>
    </section>
  `;

  if (isLogged) {
    document.getElementById("btn-vote").addEventListener("click", doVote);
    document.getElementById("btn-unvote").addEventListener("click", doUnvote);
    contentEl.querySelectorAll("[data-st]").forEach(btn => {
      btn.addEventListener("click", () => doStatus(btn.dataset.st));
    });
    document.getElementById("cm-form").addEventListener("submit", onCommentSubmit);
  }

  // Share / copy link
  document.getElementById("btn-share").addEventListener("click", () => {
    const url = window.location.href.split("#")[0];
    if (navigator.share) {
      navigator.share({ title: o.occTitle, text: o.occDescription, url }).catch(() => {});
    } else {
      copyToClipboard(url);
    }
  });
  document.getElementById("btn-copy-link").addEventListener("click", () => {
    copyToClipboard(window.location.href.split("#")[0]);
  });

  // Copiar CEP
  contentEl.querySelectorAll(".copy-cep-btn").forEach(b => {
    b.addEventListener("click", () => copyToClipboard(b.dataset.cep));
  });

  // Lightbox na foto (só se houver foto real, não fallback SVG)
  const img = contentEl.querySelector(".detail-img");
  if (img && img.dataset.zoom) {
    img.classList.add("zoomable");
    img.addEventListener("click", () => openLightbox(img.dataset.zoom, o.occTitle));
  }

  loadComments();
}

function copyToClipboard(text) {
  navigator.clipboard.writeText(text).then(
    () => toast("Link copiado!", "success"),
    () => {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      ta.remove();
      toast("Link copiado!", "success");
    }
  );
}

// ---------- Comments ---------------------------------------------------------

async function loadComments() {
  try {
    const list = await Api.listComments(occId);
    renderComments(list);
  } catch (err) {
    const el = document.getElementById("cm-list");
    if (el) el.innerHTML = `<div class="empty-mini">erro ao carregar: ${escapeHtml(err.message)}</div>`;
  }
}

function renderComments(list) {
  const el  = document.getElementById("cm-list");
  const cnt = document.getElementById("cm-count");
  if (cnt) cnt.textContent = `${list.length} ${list.length === 1 ? "comentário" : "comentários"}`;
  if (!el) return;
  if (list.length === 0) {
    el.innerHTML = `<div class="empty-mini">Ainda sem comentários. Seja a primeira voz.</div>`;
    return;
  }
  el.innerHTML = list.map(commentHtml).join("");
  el.querySelectorAll("[data-act='del']").forEach(btn => {
    btn.addEventListener("click", () => deleteComment(Number(btn.dataset.id)));
  });
  el.querySelectorAll("[data-act='edit']").forEach(btn => {
    btn.addEventListener("click", () => openEditComment(Number(btn.dataset.id)));
  });
  el.querySelectorAll("[data-act='cancel-edit']").forEach(btn => {
    btn.addEventListener("click", () => closeEditComment(Number(btn.dataset.id)));
  });
  el.querySelectorAll("[data-act='save-edit']").forEach(btn => {
    btn.addEventListener("click", () => saveEditComment(Number(btn.dataset.id)));
  });
}

function commentHtml(c) {
  const mine    = isLogged && c.commentUserId === user.userId;
  const isAdmin = isLogged && user.userRole === "admin";
  const showDel = mine || isAdmin;
  const showEdit = mine; // só o autor pode editar
  return `
    <article class="comment" data-cid="${c.commentId}">
      <div class="comment-avatar">${escapeHtml(c.commentUsername[0] || "?").toUpperCase()}</div>
      <div class="comment-main">
        <div class="comment-head">
          <strong>@${escapeHtml(c.commentUsername)}</strong>
          <span class="comment-time">${timeAgo(c.commentCreatedAt)}</span>
          <span class="comment-actions">
            ${showEdit ? `<button type="button" class="comment-action-btn" data-act="edit" data-id="${c.commentId}" aria-label="Editar">Editar</button>` : ""}
            ${showDel  ? `<button type="button" class="comment-action-btn danger" data-act="del" data-id="${c.commentId}" aria-label="Apagar">×</button>` : ""}
          </span>
        </div>
        <div class="comment-body" id="cm-body-${c.commentId}">${escapeHtml(c.commentBody)}</div>
        <div class="comment-edit-area" id="cm-edit-${c.commentId}" style="display:none;">
          <textarea class="comment-edit-textarea" maxlength="1000">${escapeHtml(c.commentBody)}</textarea>
          <div class="comment-edit-actions">
            <button type="button" class="btn small secondary" data-act="cancel-edit" data-id="${c.commentId}">Cancelar</button>
            <button type="button" class="btn small" data-act="save-edit" data-id="${c.commentId}">Salvar</button>
          </div>
        </div>
      </div>
    </article>`;
}

async function onCommentSubmit(e) {
  e.preventDefault();
  const body = document.getElementById("cm-body").value.trim();
  if (!body) return;
  const btn = document.getElementById("cm-submit");
  btn.disabled = true;
  btn.textContent = "…";
  try {
    await Api.createComment(occId, body, Auth.token());
    document.getElementById("cm-body").value = "";
    await loadComments();
    toast("comentário publicado");
  } catch (err) {
    if (err.status === 401) { Auth.logout(); window.location.replace("login.html"); return; }
    toast(err.message || "erro ao comentar", "error");
  } finally {
    btn.disabled = false;
    btn.textContent = "Publicar";
  }
}

function openEditComment(cid) {
  const bodyEl = document.getElementById(`cm-body-${cid}`);
  const editEl = document.getElementById(`cm-edit-${cid}`);
  if (!bodyEl || !editEl) return;
  bodyEl.style.display = "none";
  editEl.style.display = "";
  editEl.querySelector("textarea").focus();
}

function closeEditComment(cid) {
  const bodyEl = document.getElementById(`cm-body-${cid}`);
  const editEl = document.getElementById(`cm-edit-${cid}`);
  if (!bodyEl || !editEl) return;
  bodyEl.style.display = "";
  editEl.style.display = "none";
}

async function saveEditComment(cid) {
  const editEl = document.getElementById(`cm-edit-${cid}`);
  if (!editEl) return;
  const textarea = editEl.querySelector("textarea");
  const body = textarea.value.trim();
  if (!body) return;
  const saveBtn = editEl.querySelector("[data-act='save-edit']");
  saveBtn.disabled = true;
  saveBtn.textContent = "…";
  try {
    await Api.editComment(cid, body, Auth.token());
    await loadComments();
    toast("comentário editado");
  } catch (err) {
    if (err.status === 401) { Auth.logout(); window.location.replace("login.html"); return; }
    toast(err.message || "erro ao editar comentário", "error");
    saveBtn.disabled = false;
    saveBtn.textContent = "Salvar";
  }
}

async function deleteComment(cid) {
  if (!confirm("Apagar este comentário?")) return;
  try {
    await Api.deleteComment(cid, Auth.token());
    await loadComments();
  } catch (err) {
    toast(err.message || "erro ao apagar", "error");
  }
}

function timeAgo(iso) {
  const d = new Date(iso);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "agora";
  if (diff < 3600) return `há ${Math.floor(diff/60)} min`;
  if (diff < 86400) return `há ${Math.floor(diff/3600)}h`;
  if (diff < 604800) return `há ${Math.floor(diff/86400)}d`;
  return d.toLocaleDateString("pt-BR");
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
function openLightbox(url, title) {
  const lb = document.createElement("div");
  lb.className = "lightbox-bg";
  lb.innerHTML = `
    <button class="lightbox-close" aria-label="Fechar">×</button>
    <img class="lightbox-img" src="${escapeAttr(url)}" alt="${escapeAttr(title || "")}" />
    ${title ? `<div class="lightbox-caption">${escapeHtml(title)}</div>` : ""}
  `;
  document.body.appendChild(lb);
  document.body.classList.add("lightbox-open");
  const close = () => { lb.remove(); document.body.classList.remove("lightbox-open"); };
  lb.addEventListener("click", (e) => { if (e.target === lb || e.target.classList.contains("lightbox-close")) close(); });
  const esc = (e) => { if (e.key === "Escape") { close(); document.removeEventListener("keydown", esc); } };
  document.addEventListener("keydown", esc);
}

function fallbackSvg(id, title) {
  const n = Number(id) || (title?.length ?? 7);
  const palette = [
    ["#10b981","#0f766e"],["#f59e0b","#b45309"],["#3b82f6","#1d4ed8"],
    ["#ec4899","#be185d"],["#8b5cf6","#6d28d9"],["#06b6d4","#0e7490"]
  ];
  const [c1,c2] = palette[n % palette.length];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 520"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/></linearGradient></defs><rect width="1200" height="520" fill="url(#g)"/><g transform="translate(600 220)" fill="white" opacity="0.92"><path d="M0 -90 C-50 -90 -90 -50 -90 0 C-90 60 0 150 0 150 C0 150 90 60 90 0 C90 -50 50 -90 0 -90 Z"/><circle cx="0" cy="0" r="32" fill="${c2}"/></g><text x="600" y="430" text-anchor="middle" font-family="system-ui,sans-serif" font-size="32" font-weight="600" fill="rgba(255,255,255,0.85)">ZelaAi</text></svg>`;
  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
}

function timeAgoLong(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "agora mesmo";
  if (diff < 3600) return `há ${Math.floor(diff/60)} min`;
  if (diff < 86400) return `há ${Math.floor(diff/3600)} h`;
  if (diff < 604800) return `há ${Math.floor(diff/86400)} d`;
  return `em ${d.toLocaleDateString("pt-BR")}`;
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

mountKeyboardShortcuts({
  onEsc: () => {},
});
