import { escapeHtml } from "./util.js";
// =============================================================================
// ZelaAi — utilitário ViaCEP: máscara + autocomplete de cidade/UF
// Uso:  attachCepLookup(inputEl, hintEl, { onResult })
// =============================================================================

const CACHE = new Map();

export function attachCepLookup(input, hint, { onResult } = {}) {
  if (!input) return;
  const defaultHintHtml = hint ? hint.innerHTML : "";
  let timer = null;

  input.addEventListener("input", (e) => {
    const raw = e.target.value.replace(/\D/g, "").slice(0, 8);
    e.target.value = raw.length > 5 ? `${raw.slice(0,5)}-${raw.slice(5)}` : raw;

    clearTimeout(timer);
    if (raw.length !== 8) {
      if (hint) {
        hint.innerHTML = defaultHintHtml;
        hint.classList.remove("ok", "err");
      }
      return;
    }
    timer = setTimeout(() => lookup(raw, hint, onResult), 300);
  });
}

async function lookup(cep, hint, onResult) {
  if (CACHE.has(cep)) {
    return apply(CACHE.get(cep), hint, onResult);
  }
  if (hint) {
    hint.classList.remove("ok", "err");
    hint.innerHTML = `<span class="spinner" style="width:11px;height:11px;border-width:1.5px;"></span> buscando ${cep}…`;
  }
  try {
    const r = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
    const j = await r.json();
    if (j.erro) throw new Error("CEP não encontrado");
    const result = { cep, city: j.localidade, uf: j.uf, street: j.logradouro, neighborhood: j.bairro };
    CACHE.set(cep, result);
    apply(result, hint, onResult);
  } catch (err) {
    if (hint) {
      hint.classList.add("err");
      hint.classList.remove("ok");
      hint.textContent = err.message || "CEP inválido";
    }
    if (onResult) onResult(null, err);
  }
}

function apply(result, hint, onResult) {
  if (hint) {
    hint.classList.add("ok");
    hint.classList.remove("err");
    const parts = [];
    if (result.street) parts.push(escapeHtml(result.street));
    parts.push(`${escapeHtml(result.city)}/${escapeHtml(result.uf)}`);
    hint.innerHTML = `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" style="color:var(--primary);"><polyline points="20 6 9 17 4 12"/></svg> ${parts.join(" · ")}`;
  }
  if (onResult) onResult(result, null);
}

