// =============================================================================
// ZelaAi — gerenciamento de tema (dark/light)
// Persiste em localStorage; respeita prefers-color-scheme no primeiro acesso.
// =============================================================================

const KEY = "zelaai.theme";

export const Theme = {
  current() {
    return document.documentElement.getAttribute("data-theme") || "light";
  },

  apply(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem(KEY, theme);
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", theme === "dark" ? "#0a1612" : "#0f9d58");
  },

  toggle() {
    this.apply(this.current() === "dark" ? "light" : "dark");
  },

  init() {
    const saved = localStorage.getItem(KEY);
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    this.apply(saved || (prefersDark ? "dark" : "light"));
  },

  mountToggle(host) {
    if (!host) return;
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "theme-toggle";
    btn.setAttribute("aria-label", "Alternar tema");
    btn.innerHTML = `
      <svg class="th-sun"  viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>
      <svg class="th-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
    `;
    btn.addEventListener("click", () => this.toggle());
    host.appendChild(btn);
  },
};

// roda assim que o módulo é importado para evitar flash
Theme.init();

// se o usuário logado é admin, insere o link "Admin" na nav
(function injectAdminLink() {
  try {
    const raw = localStorage.getItem("zelaai.session");
    if (!raw) return;
    const sess = JSON.parse(raw);
    if (sess?.user?.userRole !== "admin") return;
    document.addEventListener("DOMContentLoaded", () => {
      const nav = document.querySelector(".nav-links");
      if (!nav || nav.querySelector('a[href="admin.html"]')) return;
      const a = document.createElement("a");
      a.href = "admin.html";
      a.textContent = "Admin";
      if (location.pathname.endsWith("admin.html")) a.classList.add("active");
      nav.appendChild(a);
    });
  } catch (_) {}
})();
