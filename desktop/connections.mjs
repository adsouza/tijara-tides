import {serverUrl} from "./server-url.mjs";

export const DEFAULT_SERVER = "https://tijara.adsouza.net/";
export const HISTORY_LIMIT = 10;
const LAST_KEY = "tijara-tides:server";
const HISTORY_KEY = "tijara-tides:servers";

function valid(value) {
  try { return serverUrl(value); } catch { return null; }
}

export function loadConnections(storage) {
  let last;
  let recent = [];
  try { last = valid(storage.getItem(LAST_KEY)); } catch {}
  try {
    const saved = JSON.parse(storage.getItem(HISTORY_KEY));
    if (Array.isArray(saved)) recent = saved.map(valid).filter(Boolean);
  } catch {}
  last ||= recent[0] || DEFAULT_SERVER;
  return {last, recent: [...new Set([last, ...recent])].slice(0, HISTORY_LIMIT)};
}

export function rememberConnection(storage, value) {
  const url = serverUrl(value);
  const {recent} = loadConnections(storage);
  const next = [url, ...recent.filter(item => item !== url)].slice(0, HISTORY_LIMIT);
  try {
    storage.setItem(HISTORY_KEY, JSON.stringify(next));
    storage.setItem(LAST_KEY, url);
  } catch {}
  return url;
}

export function playUrl(value) {
  const url = new URL(serverUrl(value));
  if (url.pathname === "/") url.pathname = "/play";
  return url.href;
}

export function shouldAutoConnect(hash) {
  return hash !== "#settings";
}
