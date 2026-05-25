// =============================================================================
// ZelaAi — sessão local (JWT + user no localStorage)
// =============================================================================

const STORAGE_KEY = "zelaai.session";

export const Auth = {
  save({ token, user }) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ token, user }));
  },

  get() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (_) {
      return null;
    }
  },

  token() {
    const s = this.get();
    return s ? s.token : null;
  },

  user() {
    const s = this.get();
    return s ? s.user : null;
  },

  isLogged() {
    return !!this.token();
  },

  logout() {
    localStorage.removeItem(STORAGE_KEY);
  },

  requireAuth(redirectTo = "login.html") {
    if (!this.isLogged()) {
      window.location.replace(redirectTo);
    }
  },
};

// helper de toast global
export function toast(msg, kind = "info") {
  let el = document.querySelector(".toast");
  if (!el) {
    el = document.createElement("div");
    el.className = "toast";
    document.body.appendChild(el);
  }
  el.textContent = msg;
  el.className = "toast " + (kind === "error" ? "error" : "");
  requestAnimationFrame(() => el.classList.add("show"));
  setTimeout(() => el.classList.remove("show"), 2500);
}
