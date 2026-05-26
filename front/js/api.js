// =============================================================================
// ZelaAi — cliente HTTP da API
// Todos endpoints encapsulados aqui. Cada handler joga ApiError no fail.
// =============================================================================

// Resolução do API_BASE — ordem de prioridade:
//   1. <meta name="api-base" content="..."> no HTML (injetado pelo deploy)
//   2. window.ZELAAI_API_BASE (config inline antes de carregar este módulo)
//   3. mesmo host:5050 se estiver em localhost / 127.0.0.1 (dev)
//   4. mesmo host sem porta (produção, atrás do mesmo domínio/proxy)
function resolveApiBase() {
  const meta = document.querySelector('meta[name="api-base"]');
  if (meta && meta.content) return meta.content.replace(/\/$/, "");
  if (typeof window.ZELAAI_API_BASE === "string" && window.ZELAAI_API_BASE)
    return window.ZELAAI_API_BASE.replace(/\/$/, "");
  const { protocol, hostname } = window.location;
  if (hostname === "localhost" || hostname === "127.0.0.1")
    return `${protocol}//${hostname}:5050`;
  return `${protocol}//${hostname}`;
}
const API_BASE = resolveApiBase();

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ---------- Cold-start UX ---------------------------------------------------
// Em deploys free (Render, Fly), o backend dorme após inatividade e demora
// 30-60s para acordar. Mostra um banner discreto e faz retry transparente.
const COLD_START_THRESHOLD_MS = 2000;
let coldStartBanner = null;
let inflightRequests = 0;
let coldStartTimer = null;

function showColdStartBanner() {
  if (coldStartBanner) return;
  coldStartBanner = document.createElement("div");
  coldStartBanner.className = "cold-banner";
  coldStartBanner.innerHTML = `
    <span class="cold-spinner"></span>
    <div>
      <strong>Acordando servidor…</strong>
      <small>O backend estava dormindo (free tier). Aguarde ~30s.</small>
    </div>
  `;
  document.body.appendChild(coldStartBanner);
  requestAnimationFrame(() => coldStartBanner.classList.add("show"));
}
function hideColdStartBanner() {
  if (!coldStartBanner) return;
  coldStartBanner.classList.remove("show");
  const el = coldStartBanner;
  coldStartBanner = null;
  setTimeout(() => el.remove(), 250);
}
function trackStart() {
  inflightRequests += 1;
  if (inflightRequests === 1) {
    coldStartTimer = setTimeout(showColdStartBanner, COLD_START_THRESHOLD_MS);
  }
}
function trackEnd() {
  inflightRequests = Math.max(0, inflightRequests - 1);
  if (inflightRequests === 0) {
    clearTimeout(coldStartTimer);
    coldStartTimer = null;
    hideColdStartBanner();
  }
}

async function request(method, path, { body, token, _retried = 0 } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const init = { method, headers };
  if (body !== undefined) init.body = JSON.stringify(body);

  trackStart();
  let resp;
  try {
    resp = await fetch(`${API_BASE}${path}`, init);
  } catch (e) {
    // retry 1x após 2s — cobre o caso clássico do cold-start onde o primeiro
    // SYN é rejeitado mas o segundo já encontra o servidor acordado
    if (_retried < 2 && method === "GET") {
      trackEnd();
      await sleep(2000);
      return request(method, path, { body, token, _retried: _retried + 1 });
    }
    trackEnd();
    throw new ApiError(0, "rede indisponível — backend offline?");
  } finally {
    if (resp) trackEnd();
  }

  // 502/503/504 do Render durante cold-start: retry uma vez
  if ((resp.status === 502 || resp.status === 503 || resp.status === 504) && _retried < 2 && method === "GET") {
    await sleep(2000);
    return request(method, path, { body, token, _retried: _retried + 1 });
  }

  let payload = null;
  const text = await resp.text();
  if (text) {
    try { payload = JSON.parse(text); } catch (_) { payload = text; }
  }

  if (!resp.ok) {
    const msg = (payload && payload.message) || resp.statusText || "erro";
    throw new ApiError(resp.status, msg);
  }
  return payload;
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------- Users ----------
export const Api = {
  register({ name, username, password, cep }) {
    return request("POST", "/users/register", {
      body: { name, username, password, cep },
    });
  },

  login({ username, password }) {
    return request("POST", "/users/login", {
      body: { loginUsername: username, loginPassword: password },
    });
  },

  // ---------- Categories ----------
  listCategories() {
    return request("GET", "/categories");
  },

  // ---------- Occurrences ----------
  listOccurrences() {
    return request("GET", "/occurrences");
  },

  getOccurrence(id) {
    return request("GET", `/occurrences/${id}`);
  },

  listOccurrencesByCep(cep) {
    return request("GET", `/occurrences/by-location?cep=${encodeURIComponent(cep)}`);
  },

  createOccurrence(payload, token) {
    return request("POST", "/occurrences", { body: payload, token });
  },

  updateStatus(id, newStatus, token) {
    return request("PATCH", `/occurrences/${id}/status`, { body: { newStatus }, token });
  },

  myOccurrences(token) {
    return request("GET", "/users/me/occurrences", { token });
  },

  // ---------- Votes ----------
  vote(occId, token) {
    return request("POST", `/occurrences/${occId}/vote`, { token });
  },

  unvote(occId, token) {
    return request("DELETE", `/occurrences/${occId}/vote`, { token });
  },

  // ---------- Mandates / Score ----------
  listMandates() {
    return request("GET", "/mandates");
  },

  getMandateScore(id) {
    return request("GET", `/mandates/${id}/score`);
  },

  // ---------- Occurrence edit/delete ----------
  updateOccurrence(id, patch, token) {
    return request("PATCH", `/occurrences/${id}`, { body: patch, token });
  },

  deleteOccurrence(id, token) {
    return request("DELETE", `/occurrences/${id}`, { token });
  },

  // ---------- Nearby ----------
  nearbyOccurrences(lat, lng, radiusKm = 5) {
    const q = `lat=${encodeURIComponent(lat)}&lng=${encodeURIComponent(lng)}&radiusKm=${encodeURIComponent(radiusKm)}`;
    return request("GET", `/occurrences/nearby?${q}`);
  },

  // ---------- Comments ----------
  listComments(occId) {
    return request("GET", `/occurrences/${occId}/comments`);
  },

  createComment(occId, body, token) {
    return request("POST", `/occurrences/${occId}/comments`, {
      body: { newCommentBody: body },
      token,
    });
  },

  deleteComment(id, token) {
    return request("DELETE", `/comments/${id}`, { token });
  },

  myComments(token) {
    return request("GET", "/users/me/comments", { token });
  },

  // ---------- Admin ----------
  adminListUsers(token) {
    return request("GET", "/admin/users", { token });
  },

  adminSetUserRole(uid, role, token) {
    return request("PATCH", `/admin/users/${uid}/role`, { body: { role }, token });
  },

  adminStats(token) {
    return request("GET", "/admin/stats", { token });
  },

  adminDeleteOccurrence(id, token) {
    return request("DELETE", `/admin/occurrences/${id}`, { token });
  },
};

export { ApiError };
