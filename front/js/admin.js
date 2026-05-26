// =============================================================================
// ZelaAi — Admin panel: stats + lista de usuários + alteração de role
// =============================================================================

import { Api } from "./api.js";
import { Auth, toast } from "./auth.js";
import { Theme } from "./theme.js";

Theme.mountToggle(document.querySelector(".header-actions"));

Auth.requireAuth();

const user      = Auth.user();
const userTag   = document.getElementById("user-tag");
const logoutLnk = document.getElementById("logout-link");

userTag.textContent = `@${user.userUsername}`;
logoutLnk.addEventListener("click", (e) => {
  e.preventDefault();
  Auth.logout();
  window.location.replace("login.html");
});

// gate de admin (validação cliente + servidor; servidor é a autoridade real)
if (user.userRole !== "admin") {
  document.getElementById("forbidden").style.display = "";
} else {
  document.getElementById("panel").style.display = "";
  loadAll();
}

async function loadAll() {
  try {
    const [stats, users] = await Promise.all([
      Api.adminStats(Auth.token()),
      Api.adminListUsers(Auth.token()),
    ]);
    renderStats(stats);
    renderUsers(users);
  } catch (e) {
    if (e.status === 403) {
      document.getElementById("panel").style.display = "none";
      document.getElementById("forbidden").style.display = "";
      return;
    }
    toast(e.message || "erro ao carregar", "error");
  }
}

function renderStats(s) {
  document.getElementById("adm-stats").innerHTML = `
    <div class="kpi"><div class="kpi-label">👥 Usuários</div><div class="kpi-value">${s.adminUsers}</div><div class="kpi-sub">${s.adminAdmins} admin(s)</div></div>
    <div class="kpi"><div class="kpi-label">📋 Ocorrências</div><div class="kpi-value">${s.adminOccurrences}</div><div class="kpi-sub">${s.adminDeleted} soft-deleted</div></div>
    <div class="kpi"><div class="kpi-label">👍 Votos</div><div class="kpi-value">${s.adminVotes}</div><div class="kpi-sub">soma global</div></div>
    <div class="kpi"><div class="kpi-label">💬 Comentários</div><div class="kpi-value">${s.adminComments}</div><div class="kpi-sub">${s.adminMandates} mandato(s)</div></div>
  `;
}

function renderUsers(users) {
  document.getElementById("adm-users-count").textContent = `${users.length} total`;
  const el = document.getElementById("adm-users");
  if (users.length === 0) { el.innerHTML = `<div class="empty-mini">nenhum usuário</div>`; return; }
  el.innerHTML = `
    <div class="admin-row admin-row-head">
      <div>#</div>
      <div>Username</div>
      <div>Nome</div>
      <div>Cidade/UF</div>
      <div>Role</div>
      <div></div>
    </div>
    ${users.map(rowHtml).join("")}
  `;
  el.querySelectorAll("[data-act='toggle-role']").forEach(btn => {
    btn.addEventListener("click", () => toggleRole(Number(btn.dataset.id), btn.dataset.role));
  });
}

function rowHtml(u) {
  const isMe = u.userId === user.userId;
  const next = u.userRole === "admin" ? "citizen" : "admin";
  return `
    <div class="admin-row">
      <div>${u.userId}</div>
      <div><strong>@${escapeHtml(u.userUsername)}</strong>${isMe ? " <small>(você)</small>" : ""}</div>
      <div>${escapeHtml(u.userName)}</div>
      <div>${escapeHtml(u.userCity || "—")}${u.userUf ? "/" + escapeHtml(u.userUf) : ""}</div>
      <div><span class="badge ${u.userRole === "admin" ? "resolved" : "in_progress"}" style="text-transform:lowercase;">${escapeHtml(u.userRole)}</span></div>
      <div>${isMe
        ? `<button class="btn ghost small" disabled title="você mesmo">—</button>`
        : `<button class="btn ghost small" data-act="toggle-role" data-id="${u.userId}" data-role="${next}">→ ${next}</button>`
      }</div>
    </div>
  `;
}

async function toggleRole(uid, newRole) {
  if (!confirm(`Promover/rebaixar este usuário para ${newRole}?`)) return;
  try {
    await Api.adminSetUserRole(uid, newRole, Auth.token());
    toast(`role alterada para ${newRole}`, "success");
    await loadAll();
  } catch (e) {
    toast(e.message || "erro ao alterar role", "error");
  }
}

function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, ch => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  }[ch]));
}
