import { Api, ApiError } from "./api.js";
import { Auth, toast } from "./auth.js";
import { Theme } from "./theme.js";
import { attachCepLookup } from "./cep.js";

Theme.mountToggle(document.getElementById("auth-top-actions"));

// auto-completa cidade/UF do CEP no signup
attachCepLookup(
  document.getElementById("su-cep"),
  document.getElementById("su-cep-hint")
);

// Se já estiver logado, manda direto pro feed
if (Auth.isLogged()) {
  window.location.replace("index.html");
}

const tabLogin  = document.getElementById("tab-login");
const tabSignup = document.getElementById("tab-signup");
const formLogin = document.getElementById("form-login");
const formSignup = document.getElementById("form-signup");

function showTab(which) {
  const isLogin = which === "login";
  tabLogin.classList.toggle("active", isLogin);
  tabSignup.classList.toggle("active", !isLogin);
  formLogin.style.display  = isLogin ? "" : "none";
  formSignup.style.display = isLogin ? "none" : "";
}
tabLogin.addEventListener("click", () => showTab("login"));
tabSignup.addEventListener("click", () => showTab("signup"));

// ----- LOGIN
formLogin.addEventListener("submit", async (e) => {
  e.preventDefault();
  const btn = document.getElementById("btn-login");
  btn.disabled = true; btn.textContent = "Entrando...";
  try {
    const res = await Api.login({
      username: document.getElementById("login-username").value.trim(),
      password: document.getElementById("login-password").value,
    });
    Auth.save({ token: res.token, user: res.user });
    window.location.replace("index.html");
  } catch (err) {
    toast(err.message || "falha no login", "error");
    btn.disabled = false; btn.textContent = "Entrar";
  }
});

// ----- SIGNUP
formSignup.addEventListener("submit", async (e) => {
  e.preventDefault();
  const btn = document.getElementById("btn-signup");
  const cep = document.getElementById("su-cep").value.replace(/\D/g, "");
  if (!/^\d{8}$/.test(cep)) {
    toast("CEP precisa ter 8 dígitos", "error");
    return;
  }
  btn.disabled = true; btn.textContent = "Criando...";
  try {
    await Api.register({
      name:     document.getElementById("su-name").value.trim(),
      username: document.getElementById("su-username").value.trim(),
      password: document.getElementById("su-password").value,
      cep,
    });
    toast("Conta criada! Faça login.");
    showTab("login");
    document.getElementById("login-username").value = document.getElementById("su-username").value;
  } catch (err) {
    toast(err.message || "falha no cadastro", "error");
  } finally {
    btn.disabled = false; btn.textContent = "Criar conta";
  }
});
