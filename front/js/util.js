// ZelaAi — utilidades compartilhadas entre as páginas.
// Centraliza funções que estavam duplicadas em 5+ arquivos.

// --------------------------------------------------------- escape HTML / attr
export function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, ch => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  }[ch]));
}
export function escapeAttr(s) { return escapeHtml(s); }

// --------------------------------------------------------- status helpers
export function labelStatus(s) {
  return ({
    open: "Aberto",
    in_progress: "Em andamento",
    resolved: "Resolvido",
  })[s] || s;
}

export function statusColor(s) {
  return s === "resolved" ? "#0f9d58"
       : s === "in_progress" ? "#3b82f6"
       : "#f59e0b";
}

// --------------------------------------------------------- date helpers
export function fmtDate(iso) {
  try {
    return new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
  } catch { return String(iso); }
}

export function fmtDateTime(iso) {
  try {
    return new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
  } catch { return ""; }
}

// versão curta: "agora", "há 5 min", "há 3h", "há 2d", ou data
export function timeAgo(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "agora";
  if (diff < 3600) return `há ${Math.floor(diff / 60)} min`;
  if (diff < 86400) return `há ${Math.floor(diff / 3600)}h`;
  if (diff < 604800) return `há ${Math.floor(diff / 86400)}d`;
  return d.toLocaleDateString("pt-BR");
}

// --------------------------------------------------------- SVG placeholder
// Gera um data URI determinístico baseado no id, sem dependência externa.
export function fallbackImage(idLike, { w = 720, h = 360 } = {}) {
  const n = Number(idLike) || (String(idLike || "").length ?? 7);
  const palette = [
    ["#10b981", "#0f766e"], ["#f59e0b", "#b45309"],
    ["#3b82f6", "#1d4ed8"], ["#ec4899", "#be185d"],
    ["#8b5cf6", "#6d28d9"], ["#06b6d4", "#0e7490"],
  ];
  const [c1, c2] = palette[n % palette.length];
  const r = Math.min(w, h) * 0.18;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}">
    <defs>
      <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/>
      </linearGradient>
    </defs>
    <rect width="${w}" height="${h}" fill="url(#g)"/>
    <g transform="translate(${w / 2} ${h * 0.45})" fill="white" opacity="0.92">
      <path d="M0 ${-r} C${-r * 0.55} ${-r} ${-r} ${-r * 0.55} ${-r} 0 C${-r} ${r * 0.67} 0 ${r * 1.67} 0 ${r * 1.67} C0 ${r * 1.67} ${r} ${r * 0.67} ${r} 0 C${r} ${-r * 0.55} ${r * 0.55} ${-r} 0 ${-r} Z"/>
      <circle cx="0" cy="0" r="${r * 0.37}" fill="${c2}"/>
    </g>
    <text x="${w / 2}" y="${h - 30}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="${Math.round(w * 0.03)}" font-weight="600" fill="rgba(255,255,255,0.85)">ZelaAi</text>
  </svg>`;
  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
}
