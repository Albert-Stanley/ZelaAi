// ZelaAi — atalhos de teclado globais
// n = nova ocorrência | Esc = fechar modal | / = foco na busca | ? = ajuda

export function mountKeyboardShortcuts({ onNew, onSearch, onEsc } = {}) {
  const helpEl = buildHelpModal();
  document.body.appendChild(helpEl);

  document.addEventListener("keydown", (e) => {
    // ignora quando usuário está digitando em campo de texto
    const tag = document.activeElement?.tagName;
    const inInput = tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT"
      || document.activeElement?.isContentEditable;

    if (e.key === "Escape") {
      e.preventDefault();
      helpEl.classList.remove("open");
      onEsc?.();
      return;
    }

    if (inInput) return;

    if (e.key === "n" || e.key === "N") {
      e.preventDefault();
      onNew?.();
      return;
    }

    if (e.key === "/" ) {
      e.preventDefault();
      onSearch?.();
      return;
    }

    if (e.key === "?") {
      e.preventDefault();
      helpEl.classList.toggle("open");
      return;
    }
  });
}

function buildHelpModal() {
  const el = document.createElement("div");
  el.className = "kbd-help-bg";
  el.innerHTML = `
    <div class="kbd-help">
      <div class="kbd-help-head">
        <h3>Atalhos de teclado</h3>
        <button class="kbd-help-close" aria-label="Fechar">×</button>
      </div>
      <ul class="kbd-list">
        <li><kbd>n</kbd><span>Nova ocorrência</span></li>
        <li><kbd>/</kbd><span>Focar na busca</span></li>
        <li><kbd>Esc</kbd><span>Fechar modal / painel</span></li>
        <li><kbd>?</kbd><span>Esta ajuda</span></li>
      </ul>
    </div>
  `;
  el.addEventListener("click", (e) => {
    if (e.target === el || e.target.classList.contains("kbd-help-close")) {
      el.classList.remove("open");
    }
  });
  return el;
}
