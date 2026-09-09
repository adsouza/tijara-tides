#!/usr/bin/env python3
"""Run isolated game tests against a disposable local PostgreSQL cluster."""
import argparse
import os
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cover', action='store_true', help='Report Elixir line coverage and write HTML to cover/.')
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
# PostgreSQL 18 on macOS requires an explicit valid locale during startup.
# Use the same deterministic environment for every child, including cleanup.
env=os.environ.copy()
env['LC_ALL']='C'
env.pop('DATABASE_URL',None)
env.pop('DATABASE_URL_POOLED',None)
env.pop('TIJARA_LOCAL_DB_PORT',None)
env.pop('PHX_SERVER',None)
with tempfile.TemporaryDirectory(prefix='tj-pg-',dir='/tmp') as directory:
    base=Path(directory)
    with socket.socket() as probe:
        probe.bind(('127.0.0.1',0)); port=probe.getsockname()[1]
    subprocess.run([str(bin_dir/'initdb'),'-D',str(base/'data'),'-U','postgres','--auth=trust','--no-locale','--encoding=UTF8'],check=True,stdout=subprocess.DEVNULL,env=env)
    subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'-l',str(base/'postgres.log'),'-o',f'-h 127.0.0.1 -p {port} -k {base}','-w','start'],check=True,stdout=subprocess.DEVNULL,env=env)
    try:
        env['MIX_ENV']='test'
        env['TIJARA_TEST_DB_PORT']=str(port)
        command=['mix','test','--include','game_database']
        if args.cover: command.append('--cover')
        result=subprocess.run(command,cwd=root,env=env)
    finally:
        subprocess.run([str(bin_dir/'pg_ctl'),'-D',str(base/'data'),'-m','immediate','-w','stop'],check=True,stdout=subprocess.DEVNULL,env=env)
    raise SystemExit(result.returncode)
