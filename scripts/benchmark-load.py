#!/usr/bin/env python3
"""Run the concurrent-client saturation harness against a disposable PostgreSQL cluster."""
import argparse
import os
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--clients', type=int, default=32, help='Concurrent snapshot readers.')
parser.add_argument('--writers', type=int, default=1, help='Concurrent command writers.')
parser.add_argument('--ships', type=int, default=3, help='Maximum hulls per company.')
parser.add_argument('--companies', type=int, default=1, help='Companies seeded before measuring.')
parser.add_argument('--seconds', type=int, default=10, help='Load duration.')
parser.add_argument('--tick-ms', type=int, default=5000, help='World tick interval.')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
binary=shutil.which('initdb')
if not binary:
    candidate=Path('/opt/homebrew/opt/postgresql@18/bin/initdb')
    if candidate.exists(): binary=str(candidate)
    if not binary:
        binary=next((str(p) for p in sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'),reverse=True)),None)
if not binary: raise SystemExit('Install PostgreSQL and add its bin directory to PATH.')
bin_dir=Path(binary).parent
env=os.environ.copy()
env['LC_ALL']='C'
for key in ('DATABASE_URL','DATABASE_URL_POOLED','TIJARA_LOCAL_DB_PORT','PHX_SERVER'):
    env.pop(key,None)
with tempfile.TemporaryDirectory(prefix='tj-load-',dir='/tmp') as directory:
    base=Path(directory)
    with socket.socket() as probe:
        probe.bind(('127.0.0.1',0)); port=probe.getsockname()[1]
    subprocess.run([str(bin_dir/'initdb'),'-D',str(base/'data'),'-U','postgres','--auth=trust','--no-locale','--encoding=UTF8'],check=True,stdout=subprocess.DEVNULL,env=env)
    subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'-l',str(base/'postgres.log'),'-o',f'-h 127.0.0.1 -p {port} -k {base}','-w','start'],check=True,stdout=subprocess.DEVNULL,env=env)
    try:
        env['MIX_ENV']='test'
        env['TIJARA_TEST_DB_PORT']=str(port)
        env['LOAD_CLIENTS']=str(args.clients)
        env['LOAD_SECONDS']=str(args.seconds)
        env['LOAD_TICK_MS']=str(args.tick_ms)
        env['LOAD_WRITERS']=str(args.writers)
        env['LOAD_SHIPS']=str(args.ships)
        env['LOAD_COMPANIES']=str(args.companies)
        result=subprocess.run(['mix','run','scripts/benchmark-load.exs'],cwd=root,env=env)
    finally:
        subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'-m','immediate','-w','stop'],check=True,stdout=subprocess.DEVNULL,env=env)
    raise SystemExit(result.returncode)
