#!/usr/bin/env python3
"""Run the bounded Chromium contracts exclusively against disposable PostgreSQL."""
import subprocess
from pathlib import Path
import disposable_postgres

env = disposable_postgres.environment()
env['MIX_ENV'] = 'test'
# Port 0 lets the endpoint bind its own ephemeral port; the test reads it back.
env['TIJARA_BROWSER_TEST_PORT'] = '0'
env['PORT'] = '0'
with disposable_postgres.cluster(env, prefix='tj-browser-') as port:
    env['TIJARA_TEST_DB_PORT'] = str(port)
    result = subprocess.run(['mix', 'test', 'test/browser', '--only', 'browser', '--seed', '12345'],
                            cwd=Path(__file__).resolve().parent.parent, env=env)
raise SystemExit(result.returncode)
