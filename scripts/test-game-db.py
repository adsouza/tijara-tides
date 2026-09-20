#!/usr/bin/env python3
"""Run isolated game tests against a disposable local PostgreSQL cluster."""
import argparse
import subprocess
from pathlib import Path

import disposable_postgres

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cover', action='store_true', help='Report Elixir line coverage and write HTML to cover/.')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
env=disposable_postgres.environment()

with disposable_postgres.cluster(env) as port:
    env['MIX_ENV']='test'
    env['TIJARA_TEST_DB_PORT']=str(port)
    command=['mix','test','--include','game_database']
    if args.cover: command.append('--cover')
    result=subprocess.run(command,cwd=root,env=env)

raise SystemExit(result.returncode)
