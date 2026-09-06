export function serverUrl(value) {
  let url;
  try { url = new URL(value.trim()); }
  catch { throw new Error("Enter a complete server address, including https://."); }
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) {
    throw new Error("Use HTTPS, or HTTP with localhost for local development.");
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error("Use a server address without credentials, query parameters, or a fragment.");
  }
  return url.href;
}
