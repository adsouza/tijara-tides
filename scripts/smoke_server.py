#!/usr/bin/env python3
"""Check a running production release through a simulated HTTPS reverse proxy."""
import http.client
import json
import re
import sys
import time

port = int(sys.argv[1]) if len(sys.argv) > 1 else 10000
host = "smoke.onrender.com"


def request(path, https=False):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    headers = {"Host": host}
    if https:
        headers["X-Forwarded-Proto"] = "https"
    try:
        conn.request("GET", path, headers=headers)
        response = conn.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        conn.close()


for attempt in range(60):
    try:
        status, headers, body = request("/healthz")
        if status == 200:
            break
    except (OSError, http.client.HTTPException):
        pass
    time.sleep(1)
else:
    raise RuntimeError("Server did not become healthy")

for path in ("/health", "/healthz"):
    status, headers, body = request(path)
    assert status == 200 and body == b"ok", (path, status, body)
    assert "set-cookie" not in headers, headers
status, headers, body = request("/statusz")
assert status == 503 and json.loads(body) == {"database": "not_configured"}, (status, body)
assert "set-cookie" not in headers, headers
status, headers, _ = request("/")
assert status in (301, 308), status
assert headers["location"] == f"https://{host}/", headers
status, headers, body = request("/", https=True)
assert status == 200, status
assert "Tijara Tides" in body.decode(), "Missing lobby"
assert "secure" in headers.get("set-cookie", "").lower(), "Missing secure cookie"
assets = re.findall(r'(?:src|href)="(/assets/[^"?]+)', body.decode())
assert any(path.endswith(".js") for path in assets), assets
assert any(path.endswith(".css") for path in assets), assets
for path in assets:
    status, _, body = request(path, https=True)
    assert status == 200 and body, (path, status)
print("Production smoke check passed: health, HTTPS redirect, lobby, cookie, assets")
