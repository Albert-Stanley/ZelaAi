// Footer global injetado em todas as páginas. Inclui botão "voltar ao topo".

// Mesma lógica do api.js — sem importar pra evitar acoplamento de módulos
// (footer.js é script clássico, não module).
function resolveApiBaseForFooter() {
  const meta = document.querySelector('meta[name="api-base"]');
  if (meta && meta.content) return meta.content.replace(/\/$/, "");
  if (typeof window.ZELAAI_API_BASE === "string" && window.ZELAAI_API_BASE)
    return window.ZELAAI_API_BASE.replace(/\/$/, "");
  const { protocol, hostname } = window.location;
  if (hostname === "localhost" || hostname === "127.0.0.1")
    return `${protocol}//${hostname}:5050`;
  return `${protocol}//${hostname}`;
}

(function () {
  if (document.querySelector(".site-footer")) return;
  // Botão voltar-ao-topo
  if (!document.querySelector(".back-to-top")) {
    const btt = document.createElement("button");
    btt.className = "back-to-top";
    btt.type = "button";
    btt.setAttribute("aria-label", "Voltar ao topo");
    btt.innerHTML = `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg>`;
    document.body.appendChild(btt);
    btt.addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));
    const onScroll = () => btt.classList.toggle("visible", window.scrollY > 600);
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }
  const year = new Date().getFullYear();
  // Resolve a URL do backend Haskell. Em dev (localhost), cai pro :5050
  // — sem isso, links absolutos como /docs vão pro nginx (8080) e 404am.
  const apiBase = resolveApiBaseForFooter();
  const footer = document.createElement("footer");
  footer.className = "site-footer";
  footer.innerHTML = `
    <div class="site-footer-inner">
      <div class="site-footer-brand">
        <span class="brand-mark">Z</span>
        <span>ZelaAi</span>
      </div>
      <nav class="site-footer-links" aria-label="Links do rodapé">
        <a href="index.html">Feed</a>
        <a href="dashboard.html">Dashboard</a>
        <a href="mandates.html">Gestões</a>
        <a href="my.html">Minhas</a>
        <a href="login.html">Entrar</a>
        <span class="site-footer-sep">·</span>
        <a href="${apiBase}/docs" target="_blank" rel="noopener">📖 Docs</a>
      </nav>
      <div class="site-footer-tag">
        <span class="health-badge" id="health-badge" title="Status do serviço">
          <span class="health-dot pulse"></span>
          <span class="health-text">checando…</span>
        </span>
        · © ${year} ZelaAi · Plataforma cívica de zeladoria pública · Feito com 💚 para sua cidade
      </div>
    </div>
  `;
  document.body.appendChild(footer);

  // Health check — pinga GET /health no backend Haskell e mostra status.
  const url = (apiBase || "") + "/health";
  const t0 = performance.now();
  fetch(url, { cache: "no-store" })
    .then(async (r) => {
      const ms = Math.round(performance.now() - t0);
      const j = await r.json().catch(() => ({}));
      const badge = document.getElementById("health-badge");
      if (!badge) return;
      const dot = badge.querySelector(".health-dot");
      const txt = badge.querySelector(".health-text");
      if (r.ok && j.db === "ok") {
        dot.className = "health-dot ok";
        txt.textContent = `online · ${ms}ms · v${j.version || "0.1"}`;
        badge.title = `Backend Haskell + Postgres OK (${ms}ms)`;
      } else {
        dot.className = "health-dot degraded";
        txt.textContent = "DB degradado";
      }
    })
    .catch(() => {
      const badge = document.getElementById("health-badge");
      if (!badge) return;
      badge.querySelector(".health-dot").className = "health-dot down";
      badge.querySelector(".health-text").textContent = "offline";
    });
})();
