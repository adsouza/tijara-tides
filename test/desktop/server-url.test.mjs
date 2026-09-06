import {test} from "node:test";
import assert from "node:assert/strict";
import {serverUrl} from "../../desktop/server-url.mjs";

test("accepts HTTPS and loopback development addresses", () => {
  for (const url of ["https://game.example/", "http://localhost:4000/", "http://127.0.0.1:4011/", "http://[::1]:4000/"]) {
    assert.equal(serverUrl(` ${url} `), url);
  }
});
test("rejects insecure remote addresses, credentials, and non-web URLs", () => {
  for (const url of ["garbage", "http://game.example", "http://localhost.example", "https://user:password@game.example", "https://game.example/?token=secret", "https://game.example/#token", "javascript:alert(1)", "file:///tmp/game"]) {
    assert.throws(() => serverUrl(url), undefined, url);
  }
});
