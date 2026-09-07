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
bin_dir=Path(binary).parent
base=root/'tmp/local-game'
base.mkdir(parents=True,exist_ok=True)
new=not (base/'data/PG_VERSION').exists()
if new:
    subprocess.run([str(bin_dir/'initdb'),'-D',str(base/'data'),'-U','postgres','--auth=trust','--no-locale','--encoding=UTF8'],check=True,stdout=subprocess.DEVNULL)
# TCP listens on loopback only; the filesystem cluster is private to this launcher.
subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'-l',str(base/'postgres.log'),'-o',f'-h 127.0.0.1 -p {args.db_port} -k /tmp','-w','start'],check=True)
try:
    if new:
        subprocess.run([str(bin_dir/'createdb'),'-h','127.0.0.1','-p',str(args.db_port),'-U','postgres','tijara_tides'],check=True)
    env=os.environ.copy()
    for key in ['DATABASE_URL','DATABASE_URL_POOLED','MIX_ENV','PHX_HOST','PHX_SERVER']:
        env.pop(key,None)
    env['TIJARA_LOCAL_DB_PORT']=str(args.db_port)
    env['PORT']=str(args.web_port)
    subprocess.run(['mix','run','--no-start','scripts/migrate_game.exs'],cwd=root,env=env,check=True)
    subprocess.run(['mix','assets.build'],cwd=root,env=env,check=True)
    if new or args.seed:
        subprocess.run(['mix','run','scripts/seed_game.exs'],cwd=root,env=env,check=True)
    print(f'Play at http://localhost:{args.web_port}/play. Ctrl-C stops server and database; data is retained.',flush=True)
    app=subprocess.Popen(['mix','phx.server'],cwd=root,env=env)
    try:
        app.wait()
    except KeyboardInterrupt:
        app.terminate()
        app.wait(timeout=20)
finally:
    subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'-m','fast','-w','stop'],check=True)
