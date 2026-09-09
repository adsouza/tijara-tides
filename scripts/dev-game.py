#!/usr/bin/env python3
"""Start a persistent local playtest, isolated from all inherited Neon credentials."""
import argparse
import os
import shutil
import subprocess
from pathlib import Path

root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--web-port',type=int,default=4000)
parser.add_argument('--db-port',type=int,default=55439)
parser.add_argument('--seed',action='store_true',help='issue another explicit launch-root invitation')
args=parser.parse_args()
binary=shutil.which('initdb')
if not binary:
    candidates=[Path('/opt/homebrew/opt/postgresql@18/bin/initdb')]+sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'),reverse=True)
    binary=next((str(p) for p in candidates if p.exists()),None)
if not binary: raise SystemExit('Install PostgreSQL and put initdb/pg_ctl on PATH.')
# Use a valid locale for every PostgreSQL and application subprocess.
env=os.environ.copy()
env['LC_ALL']='C'
for key in ['DATABASE_URL','DATABASE_URL_POOLED','MIX_ENV','PHX_HOST','PHX_SERVER']:
    env.pop(key,None)
bin_dir=Path(binary).parent
base=root/'tmp/local-game'
base.mkdir(parents=True,exist_ok=True)
new=not (base/'data/PG_VERSION').exists()
if new:
    subprocess.run([str(bin_dir/'initdb'),'-D',str(base/'data'),'-U','postgres','--auth=trust','--no-locale','--encoding=UTF8'],check=True,stdout=subprocess.DEVNULL,env=env)
# A previous launcher may have exited without stopping its database. Only stop
# PostgreSQL on exit when this invocation started it.
status=subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'status'],capture_output=True,text=True,env=env)
if status.returncode not in (0,3):
    raise SystemExit(status.stderr or status.stdout or 'Could not determine local database status.')
started_database=status.returncode == 3
if not started_database:
    identity=subprocess.run([str(bin_dir/'psql'),'-X','-A','-t','-h','127.0.0.1','-p',str(args.db_port),'-U','postgres','-d','postgres','-c','SHOW data_directory'],capture_output=True,text=True,env={**env,'PGCONNECT_TIMEOUT':'5'})
    if identity.returncode or Path(identity.stdout.strip()).resolve() != (base/'data').resolve():
        raise SystemExit(f'The local database is already running, but could not be verified on port {args.db_port}. Check {base / "data/postmaster.pid"} for its port and use --db-port with that value.')
    print(f'Reusing local database on port {args.db_port}; it will remain running on exit.',flush=True)
else:
    # TCP listens on loopback only; the filesystem cluster is private to this launcher.
    subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'-l',str(base/'postgres.log'),'-o',f'-h 127.0.0.1 -p {args.db_port} -k /tmp','-w','start'],check=True,env=env)
try:
    if new:
        subprocess.run([str(bin_dir/'createdb'),'-h','127.0.0.1','-p',str(args.db_port),'-U','postgres','tijara_tides'],check=True,env=env)
    env['TIJARA_LOCAL_DB_PORT']=str(args.db_port)
    env['PORT']=str(args.web_port)
    subprocess.run(['mix','run','--no-start','scripts/migrate_game.exs'],cwd=root,env=env,check=True)
    subprocess.run(['mix','assets.build'],cwd=root,env=env,check=True)
    if new or args.seed:
        subprocess.run(['mix','run','--no-start','scripts/seed_game.exs'],cwd=root,env=env,check=True)
    shutdown='server and database' if started_database else 'server (the existing database stays running)'
    print(f'Play at http://localhost:{args.web_port}/play. Ctrl-C stops {shutdown}; data is retained.',flush=True)
    app=subprocess.Popen(['mix','phx.server'],cwd=root,env=env)
    try:
        app.wait()
    except KeyboardInterrupt:
        app.terminate()
        app.wait(timeout=20)
finally:
    if started_database:
        subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'-m','fast','-w','stop'],check=True,env=env)
