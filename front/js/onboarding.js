// ZelaAi — Onboarding/coach mark de primeira visita.
// Dispara só na 1ª vez (flag em localStorage). Pode ser re-aberto por code.

const KEY = "zelaai.onboarded.v1";

const STEPS = [
  {
    title: "Bem-vindo ao ZelaAi 👋",
    body:  "É o <b>Reclame Aqui da sua cidade</b>. Reporte buracos, lixo, lâmpadas queimadas — e cobre a prefeitura junto com seus vizinhos.",
    icon:  `<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>`
  },
  {
    title: "Veja, vote e comente",
    body:  "Cada card é uma reclamação real. Vote nas mais urgentes do seu bairro — quanto mais votos, mais pressão na gestão.",
    icon:  `<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"/></svg>`
  },
  {
    title: "Reporte em 30 segundos",
    body:  "Clique no botão <b>+</b> no canto da tela. Tire uma foto, escreva o que tá rolando e marque no mapa. Pronto.",
    icon:  `<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>`
  },
  {
    title: "Cobre os políticos",
    body:  "Em <b>Gestões</b>, veja quanto cada prefeito e governador resolveu durante o mandato. Tudo transparente, baseado nos dados da plataforma.",
    icon:  `<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 14l4-4 4 4 5-5"/></svg>`
  },
];

function buildModal(idx, total) {
  const s = STEPS[idx];
  const el = document.createElement("div");
  el.className = "onboarding-bg";
  el.innerHTML = `
    <div class="onboarding-card" role="dialog" aria-modal="true" aria-labelledby="onb-title">
      <button class="onboarding-skip" type="button" aria-label="Pular">Pular</button>
      <div class="onboarding-icon">${s.icon}</div>
      <h2 id="onb-title">${s.title}</h2>
      <p>${s.body}</p>
      <div class="onboarding-dots">
        ${Array.from({length: total}, (_, i) => `<span class="onboarding-dot ${i === idx ? "active" : ""}"></span>`).join("")}
      </div>
      <div class="onboarding-actions">
        ${idx > 0 ? `<button type="button" class="btn secondary onb-prev">Voltar</button>` : `<span></span>`}
        ${idx < total - 1
          ? `<button type="button" class="btn onb-next">Próximo →</button>`
          : `<button type="button" class="btn onb-done">Começar 🚀</button>`}
      </div>
    </div>
  `;
  return el;
}

export function startOnboarding(force = false) {
  if (!force && localStorage.getItem(KEY) === "1") return;
  let idx = 0;
  const root = document.createElement("div");
  document.body.appendChild(root);

  const render = () => {
    const el = buildModal(idx, STEPS.length);
    root.replaceChildren(el);
    el.querySelector(".onboarding-skip")?.addEventListener("click", finish);
    el.querySelector(".onb-prev")?.addEventListener("click", () => { idx--; render(); });
    el.querySelector(".onb-next")?.addEventListener("click", () => { idx++; render(); });
    el.querySelector(".onb-done")?.addEventListener("click", finish);
  };

  const finish = () => {
    localStorage.setItem(KEY, "1");
    root.remove();
    document.removeEventListener("keydown", esc);
  };
  const esc = (e) => { if (e.key === "Escape") finish(); };
  document.addEventListener("keydown", esc);

  render();
}

// Expõe globalmente para debug e atalho no header
window.__zelaaiOnboard = () => startOnboarding(true);
