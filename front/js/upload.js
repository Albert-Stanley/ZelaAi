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

// Provider em uso: cloudinary (config'd) ou catbox (fallback anônimo).
function pickProvider() {
  return cloudinaryConfigured() ? "cloudinary" : "catbox";
}

export function attachUploader({ dropZone, fileInput, preview, urlInput, status }) {
  if (!dropZone || !fileInput || !urlInput) return false;
  const provider = pickProvider();

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

  async function handleFile(file) {
    if (!file.type.startsWith("image/")) {
      setStatus("Selecione um arquivo de imagem.", "err");
      return;
    }
    if (file.size > 20 * 1024 * 1024) {
      setStatus("Imagem muito grande (máx 20MB).", "err");
      return;
    }
    showLocalPreview(file);
    // Comprime client-side para economizar dados móveis. Mantém EXIF orientation
    // implicitamente via <img> (browser corrige) e exporta em JPEG 0.82.
    let toUpload = file;
    if (file.size > 600 * 1024) {
      setStatus("otimizando imagem…", "loading");
      try {
        toUpload = await compressImage(file, { maxDim: 1600, quality: 0.82 });
        const saved = ((1 - toUpload.size / file.size) * 100).toFixed(0);
        if (saved > 0) {
          setStatus(`otimizada: ${formatBytes(file.size)} → ${formatBytes(toUpload.size)} (-${saved}%)`, "ok");
        }
      } catch {
        toUpload = file; // se falhar, sobe original
      }
    }
    upload(toUpload);
  }

  function showLocalPreview(file) {
    if (!preview) return;
    const url = URL.createObjectURL(file);
    preview.innerHTML = `<img src="${url}" alt="" />`;
    preview.classList.add("has-image");
  }

  async function upload(file) {
    setStatus(`enviando ${formatBytes(file.size)}…`, "loading");
    setProgress(0);
    try {
      let resultUrl;
      if (provider === "cloudinary") {
        const cloudName = META("cloudinary-cloud-name");
        const preset    = META("cloudinary-upload-preset");
        const url = `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`;
        const form = new FormData();
        form.append("file", file);
        form.append("upload_preset", preset);
        const result = await xhrUpload(url, form, (p) => setProgress(p));
        resultUrl = result.secure_url;
      } else {
        // Fallback anônimo: catbox.moe (sem auth, retorna URL em texto puro)
        const form = new FormData();
        form.append("reqtype", "fileupload");
        form.append("fileToUpload", file);
        const result = await xhrUploadText("https://catbox.moe/user/api.php", form, (p) => setProgress(p));
        if (!/^https?:\/\//.test(result)) throw new Error(result || "resposta inválida");
        resultUrl = result.trim();
      }
      urlInput.value = resultUrl;
      setStatus(`✓ ${file.name}`, "ok");
      setProgress(100);
      if (preview) {
        preview.innerHTML = `<img src="${resultUrl}" alt="" />`;
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

// Variante para uploaders que retornam texto puro (ex.: catbox.moe).
function xhrUploadText(url, form, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress((e.loaded / e.total) * 100);
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve(xhr.responseText);
      else reject(new Error(xhr.responseText || `HTTP ${xhr.status}`));
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

// Comprime imagem usando canvas. Resize proporcional para maxDim no maior lado.
function compressImage(file, { maxDim = 1600, quality = 0.82 } = {}) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("read fail"));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error("decode fail"));
      img.onload = () => {
        const { width: w, height: h } = img;
        const scale = Math.min(1, maxDim / Math.max(w, h));
        const tw = Math.round(w * scale);
        const th = Math.round(h * scale);
        const canvas = document.createElement("canvas");
        canvas.width = tw;
        canvas.height = th;
        const ctx = canvas.getContext("2d");
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = "high";
        ctx.drawImage(img, 0, 0, tw, th);
        canvas.toBlob(
          (blob) => {
            if (!blob) return reject(new Error("blob fail"));
            const out = new File([blob], file.name.replace(/\.\w+$/, "") + ".jpg", { type: "image/jpeg" });
            // se a compressão piorou, devolve original
            resolve(out.size < file.size ? out : file);
          },
          "image/jpeg",
          quality
        );
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}
