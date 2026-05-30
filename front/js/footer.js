// Footer global injetado em todas as páginas.
(function () {
  if (document.querySelector(".site-footer")) return;
  const year = new Date().getFullYear();
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
      </nav>
      <div class="site-footer-tag">
        © ${year} ZelaAi · Plataforma cívica de zeladoria pública · Feito com 💚 para sua cidade
      </div>
    </div>
  `;
  document.body.appendChild(footer);
})();
