#!/usr/bin/env python3
"""Run the concurrent-client saturation harness against a disposable PostgreSQL cluster."""
import argparse
import subprocess
from pathlib import Path

import disposable_postgres

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--clients', type=int, default=32, help='Concurrent snapshot readers.')
parser.add_argument('--writers', type=int, default=1, help='Concurrent command writers.')
parser.add_argument('--ships', type=int, default=3, help='Maximum hulls per company.')
parser.add_argument('--companies', type=int, default=1, help='Companies seeded before measuring.')
parser.add_argument('--seconds', type=int, default=10, help='Load duration.')
parser.add_argument('--tick-ms', type=int, default=5000, help='World tick interval.')
parser.add_argument('--think-ms', type=int, default=0, help='Pause each writer between commands.')
parser.add_argument('--read-think-ms', type=int, default=0, help='Pause each reader between snapshots.')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
env=disposable_postgres.environment()

with disposable_postgres.cluster(env, prefix='tj-load-') as port:
    env['MIX_ENV']='test'
    env['TIJARA_TEST_DB_PORT']=str(port)
    env['LOAD_CLIENTS']=str(args.clients)
    env['LOAD_SECONDS']=str(args.seconds)
    env['LOAD_TICK_MS']=str(args.tick_ms)
    env['LOAD_THINK_MS']=str(args.think_ms)
    env['LOAD_READ_THINK_MS']=str(args.read_think_ms)
    env['LOAD_WRITERS']=str(args.writers)
    env['LOAD_SHIPS']=str(args.ships)
    env['LOAD_COMPANIES']=str(args.companies)
    result=subprocess.run(['mix','run','scripts/benchmark-load.exs'],cwd=root,env=env)

raise SystemExit(result.returncode)
