#!/usr/bin/env python3
"""Start a persistent local playtest, isolated from all inherited Neon credentials."""
import argparse
import getpass
import os
import shutil
import socket
import subprocess
from pathlib import Path

root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--web-port',type=int,default=4000)
parser.add_argument('--db-port',type=int,default=5432)
parser.add_argument('--db-user',default=getpass.getuser(),help='local PostgreSQL role (defaults to your OS user)')
parser.add_argument('--seed',action='store_true',help='issue another explicit launch-root invitation')
args=parser.parse_args()
# Refuse before touching logs or storage if this server is still running.
with socket.socket() as probe:
    probe.settimeout(1)
    if probe.connect_ex(('127.0.0.1', args.web_port)) == 0:
        raise SystemExit(f'Port {args.web_port} is already in use; stop that server before restarting.')
binary=shutil.which('psql')
if not binary:
    candidates=[Path('/opt/homebrew/opt/postgresql@18/bin/psql')]+sorted(Path('/usr/lib/postgresql').glob('*/bin/psql'),reverse=True)
    binary=next((str(p) for p in candidates if p.exists()),None)
if not binary: raise SystemExit('Install PostgreSQL and put psql/createdb on PATH.')
# Use a valid locale for every PostgreSQL and application subprocess.
env=os.environ.copy()
env['LC_ALL']='C'
for key in ['DATABASE_URL','DATABASE_URL_POOLED','MIX_ENV','PHX_HOST','PHX_SERVER']:
    env.pop(key,None)
bin_dir=Path(binary).parent
base=root/'tmp/local-game'
base.mkdir(parents=True,exist_ok=True)
# Always target loopback explicitly; inherited libpq settings must not redirect us.
for key in list(env):
    if key.startswith('PG'):
        env.pop(key)
env['PGCONNECT_TIMEOUT']='5'
connection=['-h','127.0.0.1','-p',str(args.db_port),'-U',args.db_user]
status=subprocess.run([str(bin_dir/'psql'),'-X','-w',*connection,'-d','postgres','-Atc',
    "SELECT 1 FROM pg_database WHERE datname = 'tijara_tides'"],
    capture_output=True,text=True,env=env)
if status.returncode:
    raise SystemExit(f'Cannot connect to local PostgreSQL on port {args.db_port}. Start the system service first.\n{status.stderr}')
new=not status.stdout.strip()
if new:
    if (base/'data/PG_VERSION').exists():
        raise SystemExit('An older playtest exists in tmp/local-game/data. Transfer its tijara_tides database to system PostgreSQL before starting to preserve your game.')
    subprocess.run([str(bin_dir/'createdb'),'-w',*connection,'--encoding=UTF8','tijara_tides'],check=True,env=env)
env['TIJARA_LOCAL_DB_PORT']=str(args.db_port)
env['TIJARA_LOCAL_DB_USER']=args.db_user
env['PORT']=str(args.web_port)
subprocess.run(['mix','run','--no-start','scripts/migrate_game.exs'],cwd=root,env=env,check=True)
subprocess.run(['mix','assets.build'],cwd=root,env=env,check=True)
if new or args.seed:
    subprocess.run(['mix','run','--no-start','scripts/seed_game.exs'],cwd=root,env=env,check=True)
print(f'Play at http://localhost:{args.web_port}/play. Ctrl-C stops the server; system PostgreSQL stays running and data is retained.',flush=True)
server_log=base/f'server-{args.web_port}.log'
print(f'Server log: {server_log} (replaced on each start).',flush=True)
# Write mode discards the previous run instead of appending indefinitely.
with server_log.open('w') as output:
    app=subprocess.Popen(['mix','phx.server'],cwd=root,env=env,stdout=output,stderr=subprocess.STDOUT)
    try:
        app.wait()
    except KeyboardInterrupt:
        app.terminate()
        app.wait(timeout=20)
