#!/usr/bin/env python3
"""Preview the 3D berth scene alone, without PostgreSQL or a game server."""
import argparse
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

root=Path(__file__).resolve().parent.parent
page=root/'scripts'/'berth-preview.html'
bundle=root/'priv'/'static'/'assets'/'js'/'berth_scene.js'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port',type=int,default=4100)
args=parser.parse_args()
building=threading.Lock()

def build():
    # The game's own esbuild profile, so the preview shows exactly what ships.
    with building:
        return subprocess.run(['mix','esbuild','tijara_tides'],cwd=root,capture_output=True,text=True)

class Preview(BaseHTTPRequestHandler):
    def do_GET(self):
        path=self.path.split('?',1)[0]
        if path=='/':
            # Rebuild on every page load; a failed build must not serve a stale scene.
            result=build()
            if result.returncode:
                return self.reply(500,'text/plain; charset=utf-8',(result.stdout+result.stderr).encode())
            return self.reply(200,'text/html; charset=utf-8',page.read_bytes())
        if path=='/assets/js/berth_scene.js':
            return self.reply(200,'text/javascript; charset=utf-8',bundle.read_bytes())
        self.send_error(404)

    def reply(self,status,kind,body):
        self.send_response(status)
        self.send_header('Content-Type',kind)
        self.send_header('Content-Length',str(len(body)))
        self.send_header('Cache-Control','no-store')
        self.end_headers()
        self.wfile.write(body)

    def log_message(self,*_):
        pass

result=build()
if result.returncode: raise SystemExit(result.stdout+result.stderr)
server=ThreadingHTTPServer(('127.0.0.1',args.port),Preview)
print(f'Berth preview at http://127.0.0.1:{args.port}/ (Ctrl-C stops it)',flush=True)
try: server.serve_forever()
except KeyboardInterrupt: pass
finally: server.server_close()
