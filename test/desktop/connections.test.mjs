import {test} from "node:test";
import assert from "node:assert/strict";
import {DEFAULT_SERVER, loadConnections, rememberConnection, playUrl, shouldAutoConnect} from "../../desktop/connections.mjs";

function storage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value)};
}

test("first launch uses production and opens the playing world", () => {
  assert.deepEqual(loadConnections(storage()), {last: DEFAULT_SERVER, recent: [DEFAULT_SERVER]});
  assert.equal(playUrl(DEFAULT_SERVER), "https://tijara-tides.onrender.com/play");
  assert.equal(playUrl("http://localhost:4017"), "http://localhost:4017/play");
  assert.equal(playUrl("https://game.example/world/ocean"), "https://game.example/world/ocean");
  assert.equal(shouldAutoConnect(""), true);
  assert.equal(shouldAutoConnect("#settings"), false);
});

test("migrates the previous single-server preference and remembers a bounded MRU list", () => {
  const store = storage({"tijara-tides:server": "http://localhost:4017"});
  assert.equal(loadConnections(store).last, "http://localhost:4017/");
  for (let i = 0; i < 12; i++) rememberConnection(store, `https://server${i}.example`);
  rememberConnection(store, " https://server5.example/ ");
  const {last, recent} = loadConnections(store);
  assert.equal(last, "https://server5.example/");
  assert.equal(recent.length, 10);
  assert.equal(recent[0], last);
  assert.equal(recent[1], "https://server11.example/");
  assert.equal(new Set(recent).size, 10);
  assert.equal(recent.includes("https://server0.example/"), false);
});

test("corrupt or unavailable storage cannot prevent connecting safely", () => {
  const store = storage({
    "tijara-tides:server": "javascript:alert(1)",
    "tijara-tides:servers": JSON.stringify([null, 12, "http://unsafe.example", "https://safe.example/"])
  });
  assert.deepEqual(loadConnections(store), {last: "https://safe.example/", recent: ["https://safe.example/"]});
  assert.equal(loadConnections(storage({"tijara-tides:servers": "invalid json"})).last, DEFAULT_SERVER);
  assert.equal(loadConnections(undefined).last, DEFAULT_SERVER);
  assert.equal(rememberConnection(undefined, DEFAULT_SERVER), DEFAULT_SERVER);
  assert.throws(() => rememberConnection(store, "https://user:secret@example.com"));
  assert.equal(loadConnections(store).last, "https://safe.example/");
});
