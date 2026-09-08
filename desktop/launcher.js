import {DEFAULT_SERVER, loadConnections, rememberConnection, playUrl, shouldAutoConnect} from "./connections.mjs";

const input = document.querySelector("#server-url");
const recent = document.querySelector("#recent-servers");
const error = document.querySelector("#error");
let storage;
try { storage = window.localStorage; } catch {}
const connections = loadConnections(storage);
input.value = connections.last;

for (const url of [...new Set([...connections.recent, DEFAULT_SERVER])]) {
  const option = document.createElement("option");
  option.value = url;
  option.textContent = url === DEFAULT_SERVER ? `Tijara Tides (production) — ${url}` : url;
  recent.append(option);
}
recent.value = connections.last;
recent.addEventListener("change", () => { input.value = recent.value; });

function connect() {
  error.hidden = true;
  try {
    const url = rememberConnection(storage, input.value);
    window.location.replace(playUrl(url));
  } catch (failure) {
    error.textContent = failure.message;
    error.hidden = false;
  }
}

document.querySelector("#connection-form").addEventListener("submit", event => {
  event.preventDefault();
  connect();
});
if (shouldAutoConnect(window.location.hash)) connect();
