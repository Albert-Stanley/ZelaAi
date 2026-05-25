// =============================================================================
// ZelaAi — cliente HTTP da API
// Todos endpoints encapsulados aqui. Cada handler joga ApiError no fail.
// =============================================================================

const API_BASE = "http://localhost:5050";

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function request(method, path, { body, token } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const init = { method, headers };
  if (body !== undefined) init.body = JSON.stringify(body);

  let resp;
  try {
    resp = await fetch(`${API_BASE}${path}`, init);
  } catch (e) {
    throw new ApiError(0, "rede indisponível — backend offline?");
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
};

export { ApiError };
