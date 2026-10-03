#!/usr/bin/env python3
"""Run isolated game tests against a disposable local PostgreSQL cluster."""
import argparse
import subprocess
from pathlib import Path

import disposable_postgres

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cover', action='store_true', help='Report Elixir line coverage and write HTML to cover/.')
parser.add_argument('--control-sweep', action='store_true', help='Run only the CI rendered command control sweep.')
parser.add_argument('mix_args', nargs=argparse.REMAINDER, help='Extra mix test arguments after --, such as -- --slowest 20.')
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
env=disposable_postgres.environment()

with disposable_postgres.cluster(env) as port:
    env['MIX_ENV']='test'
    env['TIJARA_TEST_DB_PORT']=str(port)
    # TIJARA_TEST_DB_PORT already admits :game_database in test_helper.exs. An
    # --include here would also re-admit opt-in suites that carry that tag.
    command=['mix','test']
    if args.control_sweep:
        env['TIJARA_CONTROL_SWEEP']='1'
        command=['mix','test','--only','control_sweep']
    if args.cover: command.append('--cover')
    command+=args.mix_args[1:] if args.mix_args[:1]==['--'] else args.mix_args
    result=subprocess.run(command,cwd=root,env=env)

raise SystemExit(result.returncode)
