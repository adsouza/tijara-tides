import {serverUrl} from "./server-url.mjs";
const input = document.querySelector("#server-url");
const error = document.querySelector("#error");
try { input.value = localStorage.getItem("tijara-tides:server") || ""; } catch {}
document.querySelector("#connection-form").addEventListener("submit", event => {
  event.preventDefault();
  error.hidden = true;
  try {
    const url = serverUrl(input.value);
    try { localStorage.setItem("tijara-tides:server", url); } catch {}
    window.location.assign(url);
  } catch (failure) {
    error.textContent = failure.message;
    error.hidden = false;
  }
});
