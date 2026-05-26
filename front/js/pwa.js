// =============================================================================
// ZelaAi — registro do Service Worker + botão de "Instalar app"
// Importa em qualquer página: import "./pwa.js"
// =============================================================================

// só registra quando servido por http/https (não no file://)
if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register("/sw.js", { scope: "/" })
      .catch(() => { /* silencioso — não bloqueia UX */ });
  });
}

// Captura o evento beforeinstallprompt (Chrome/Edge) e mostra um botão
// flutuante discreto convidando a instalar. Não interrompe o usuário.
let deferredPrompt = null;
const SHOWN_KEY = "zelaai.pwa.dismissed";

window.addEventListener("beforeinstallprompt", (e) => {
  e.preventDefault();
  if (sessionStorage.getItem(SHOWN_KEY) === "1") return;
  deferredPrompt = e;
  showInstallBanner();
});

function showInstallBanner() {
  if (document.querySelector(".install-banner")) return;
  const el = document.createElement("div");
  el.className = "install-banner";
  el.innerHTML = `
    <div class="install-banner-icon">
      <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>
      </svg>
    </div>
    <div class="install-banner-text">
      <strong>Instalar o ZelaAi</strong>
      <small>Acesse rápido como um app no seu dispositivo.</small>
    </div>
    <button type="button" class="install-banner-btn" data-act="install">Instalar</button>
    <button type="button" class="install-banner-close" data-act="close" aria-label="Fechar">×</button>
  `;
  document.body.appendChild(el);
  requestAnimationFrame(() => el.classList.add("show"));

  el.addEventListener("click", async (ev) => {
    const act = ev.target.closest("[data-act]")?.dataset.act;
    if (act === "install" && deferredPrompt) {
      await deferredPrompt.prompt();
      deferredPrompt = null;
      el.classList.remove("show");
      setTimeout(() => el.remove(), 280);
    } else if (act === "close") {
      sessionStorage.setItem(SHOWN_KEY, "1");
      el.classList.remove("show");
      setTimeout(() => el.remove(), 280);
    }
  });
}

// Quando o app é instalado, esconde o banner
window.addEventListener("appinstalled", () => {
  document.querySelector(".install-banner")?.remove();
  deferredPrompt = null;
});
