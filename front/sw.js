// =============================================================================
// ZelaAi — Service Worker
// Estratégia:
//   - Assets estáticos (HTML/CSS/JS/SVG): stale-while-revalidate
//   - GETs da API (mesma origin ou cross-origin para ViaCEP/Unsplash): network-first
//     com fallback ao cache (útil quando o backend dormiu)
//   - POST/PATCH/DELETE: sempre direto na rede (nunca cacheia mutações)
// =============================================================================

const VERSION    = "zelaai-v3";
const STATIC_C   = `${VERSION}-static`;
const RUNTIME_C  = `${VERSION}-runtime`;

const PRECACHE = [
  "/",
  "/index.html",
  "/dashboard.html",
  "/mandates.html",
  "/my.html",
  "/occurrence.html",
  "/login.html",
  "/css/style.css",
  "/js/api.js",
  "/js/auth.js",
  "/js/theme.js",
  "/js/cep.js",
  "/js/feed.js",
  "/js/dashboard.js",
  "/js/login.js",
  "/js/my.js",
  "/js/mandates.js",
  "/js/occurrence.js",
  "/assets/favicon.svg",
  "/assets/og-image.svg",
  "/manifest.json",
];

self.addEventListener("install", (e) => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(STATIC_C).then((cache) =>
      // tolerante a falhas individuais (algum asset pode não existir)
      Promise.allSettled(PRECACHE.map((p) => cache.add(p)))
    )
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => !k.startsWith(VERSION))
          .map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return; // mutações sempre direto na rede

  const url = new URL(req.url);

  // Mapa de tiles do Leaflet: deixa o browser cuidar
  if (url.hostname.includes("basemaps.cartocdn.com")) return;

  // Mesma origin -> stale-while-revalidate
  if (url.origin === self.location.origin) {
    event.respondWith(staleWhileRevalidate(req));
    return;
  }

  // Cross-origin (Unsplash, ViaCEP, Chart.js CDN): network-first com fallback
  event.respondWith(networkFirst(req));
});

async function staleWhileRevalidate(req) {
  const cache = await caches.open(STATIC_C);
  const cached = await cache.match(req);
  const networkPromise = fetch(req)
    .then((resp) => {
      if (resp && resp.ok) cache.put(req, resp.clone());
      return resp;
    })
    .catch(() => cached); // se rede falhar e tiver cache, devolve cache
  return cached || networkPromise;
}

async function networkFirst(req) {
  const cache = await caches.open(RUNTIME_C);
  try {
    const resp = await fetch(req);
    if (resp && resp.ok) cache.put(req, resp.clone());
    return resp;
  } catch (_) {
    const cached = await cache.match(req);
    if (cached) return cached;
    throw _;
  }
}
