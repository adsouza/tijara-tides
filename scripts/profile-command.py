#!/usr/bin/env python3
"""Attribute what a single command spends its time on, against a disposable PostgreSQL cluster."""
import argparse
import subprocess
from pathlib import Path

import disposable_postgres

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--commands', type=int, default=100, help='Borrow/repay rounds measured.')
parser.add_argument('--ships', type=int, default=6, help='Maximum hulls per company.')
parser.add_argument('--companies', type=int, default=150, help='Companies seeded before profiling.')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
env=disposable_postgres.environment()

with disposable_postgres.cluster(env, prefix='tj-prof-') as port:
    env['MIX_ENV']='test'
    env['TIJARA_TEST_DB_PORT']=str(port)
    env['LOAD_SHIPS']=str(args.ships)
    env['LOAD_COMMANDS']=str(args.commands)
    env['LOAD_COMPANIES']=str(args.companies)
    result=subprocess.run(['mix','run','scripts/profile-command.exs'],cwd=root,env=env)

raise SystemExit(result.returncode)
