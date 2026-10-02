#!/usr/bin/env python3
"""Run the bounded Chromium contracts exclusively against disposable PostgreSQL."""
import socket
import subprocess
from pathlib import Path
import disposable_postgres

env = disposable_postgres.environment()
env['MIX_ENV'] = 'test'
with socket.socket() as probe:
    probe.bind(('127.0.0.1', 0))
    env['TIJARA_BROWSER_TEST_PORT'] = str(probe.getsockname()[1])
env['PORT'] = env['TIJARA_BROWSER_TEST_PORT']
with disposable_postgres.cluster(env, prefix='tj-browser-') as port:
    env['TIJARA_TEST_DB_PORT'] = str(port)
    result = subprocess.run(['mix', 'test', 'test/browser', '--only', 'browser', '--seed', '12345'],
                            cwd=Path(__file__).resolve().parent.parent, env=env)
raise SystemExit(result.returncode)
