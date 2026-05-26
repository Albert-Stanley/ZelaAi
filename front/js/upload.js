// =============================================================================
// ZelaAi — Upload de imagem via Cloudinary (unsigned preset)
//
// Como configurar (uma vez):
//   1. Cria conta gratuita em https://cloudinary.com  (sem cartão)
//   2. Settings -> Upload -> Add upload preset:
//        - Signing Mode: Unsigned
//        - Folder: zelaai  (opcional)
//   3. Pega o "Cloud name" do dashboard e o "Preset name" criado
//   4. Preenche as meta tags em todas as HTMLs (ou injeta no deploy):
//        <meta name="cloudinary-cloud-name"  content="seu_cloud_name" />
//        <meta name="cloudinary-upload-preset" content="seu_preset" />
//
// Se não houver config, o módulo simplesmente não monta o uploader e o
// usuário continua usando o campo "URL da foto" manualmente.
// =============================================================================

const META = (n) => document.querySelector(`meta[name="${n}"]`)?.content || "";

export function cloudinaryConfigured() {
  return Boolean(META("cloudinary-cloud-name") && META("cloudinary-upload-preset"));
}

export function attachUploader({ dropZone, fileInput, preview, urlInput, status }) {
  if (!cloudinaryConfigured()) return false;
  if (!dropZone || !fileInput || !urlInput) return false;

  dropZone.addEventListener("click", () => fileInput.click());
  dropZone.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); fileInput.click(); }
  });

  fileInput.addEventListener("change", (e) => {
    const f = e.target.files?.[0];
    if (f) handleFile(f);
  });

  // drag & drop
  ["dragenter", "dragover"].forEach(ev => dropZone.addEventListener(ev, (e) => {
    e.preventDefault(); dropZone.classList.add("drag-active");
  }));
  ["dragleave", "drop"].forEach(ev => dropZone.addEventListener(ev, (e) => {
    e.preventDefault(); dropZone.classList.remove("drag-active");
  }));
  dropZone.addEventListener("drop", (e) => {
    const f = e.dataTransfer.files?.[0];
    if (f) handleFile(f);
  });

  function handleFile(file) {
    if (!file.type.startsWith("image/")) {
      setStatus("Selecione um arquivo de imagem.", "err");
      return;
    }
    if (file.size > 8 * 1024 * 1024) {
      setStatus("Imagem muito grande (máx 8MB).", "err");
      return;
    }
    showLocalPreview(file);
    upload(file);
  }

  function showLocalPreview(file) {
    if (!preview) return;
    const url = URL.createObjectURL(file);
    preview.innerHTML = `<img src="${url}" alt="" />`;
    preview.classList.add("has-image");
  }

  async function upload(file) {
    const cloudName = META("cloudinary-cloud-name");
    const preset    = META("cloudinary-upload-preset");
    const url = `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`;
    const form = new FormData();
    form.append("file", file);
    form.append("upload_preset", preset);

    setStatus(`enviando ${formatBytes(file.size)}…`, "loading");
    setProgress(0);

    try {
      const result = await xhrUpload(url, form, (p) => setProgress(p));
      urlInput.value = result.secure_url;
      setStatus(`✓ ${file.name}`, "ok");
      setProgress(100);
      if (preview) {
        preview.innerHTML = `<img src="${result.secure_url}" alt="" />`;
        preview.classList.add("has-image");
      }
    } catch (err) {
      setStatus("erro no upload — cole uma URL manualmente abaixo", "err");
      setProgress(0);
    }
  }

  function setStatus(msg, kind) {
    if (!status) return;
    status.textContent = msg;
    status.className = "upload-status " + (kind || "");
  }

  function setProgress(pct) {
    if (!status) return;
    status.style.setProperty("--progress", `${Math.max(0, Math.min(100, pct))}%`);
  }

  return true;
}

function xhrUpload(url, form, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress((e.loaded / e.total) * 100);
    };
    xhr.onload = () => {
      try {
        const j = JSON.parse(xhr.responseText);
        if (xhr.status >= 200 && xhr.status < 300 && j.secure_url) resolve(j);
        else reject(new Error(j.error?.message || `HTTP ${xhr.status}`));
      } catch (_) { reject(new Error("resposta inválida do Cloudinary")); }
    };
    xhr.onerror = () => reject(new Error("falha de rede"));
    xhr.send(form);
  });
}

function formatBytes(b) {
  if (b < 1024) return `${b}B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(0)}KB`;
  return `${(b / 1024 / 1024).toFixed(1)}MB`;
}
