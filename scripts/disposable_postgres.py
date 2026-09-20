#!/usr/bin/env python3
"""A throwaway PostgreSQL cluster for harnesses that must never touch real storage.

Setup and teardown output is captured and printed when a step fails, together with
the server's own log. That log lives inside the temporary directory, so without
this it is deleted on the way out and a cluster that refused to start reports an
exit status and nothing else.
"""
import contextlib
import os
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path


def binaries():
    """The directory holding initdb and pg_ctl, wherever this platform keeps them."""
    binary=shutil.which('initdb')
    if not binary:
        candidate=Path('/opt/homebrew/opt/postgresql@18/bin/initdb')
        if candidate.exists(): binary=str(candidate)
        if not binary:
            binary=next((str(p) for p in sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'),reverse=True)),None)
    if not binary: raise SystemExit('Install PostgreSQL and add its bin directory to PATH.')
    return Path(binary).parent


def environment():
    """A child environment that cannot reach production or a developer's own cluster.

    PostgreSQL 18 on macOS requires an explicit valid locale during startup, and the
    same deterministic environment goes to every child, including cleanup.
    """
    env=os.environ.copy()
    env['LC_ALL']='C'
    for key in ('DATABASE_URL','DATABASE_URL_POOLED','TIJARA_LOCAL_DB_PORT','PHX_SERVER'):
        env.pop(key,None)
    return env


def step(command, env, log=None, fatal=True):
    """Run one cluster step, reporting what it printed if it fails.

    Passing check=True to subprocess.run raises with the exit status alone, which is
    how a failed start becomes an unactionable log: the cause was written to stdout
    or to the server log, and both are discarded before anyone reads them.
    """
    command=[str(part) for part in command]
    result=subprocess.run(command,env=env,capture_output=True,text=True)

    if result.returncode:
        print(f'Cluster step failed with status {result.returncode}: {" ".join(command)}')
        for name,text in (('stdout',result.stdout),('stderr',result.stderr)):
            if text and text.strip(): print(f'--- {name} ---\n{text.rstrip()}')
        if log and Path(log).exists():
            contents=Path(log).read_text().rstrip()
            if contents: print(f'--- {log} ---\n{contents}')
        if fatal: raise SystemExit(result.returncode)

    return result


@contextlib.contextmanager
def cluster(env, prefix='tj-pg-'):
    """Yield the port of a running throwaway cluster, torn down on the way out."""
    bin_dir=binaries()

    with tempfile.TemporaryDirectory(prefix=prefix,dir='/tmp') as directory:
        base=Path(directory)

        with socket.socket() as probe:
            probe.bind(('127.0.0.1',0)); port=probe.getsockname()[1]

        log=base/'postgres.log'

        step([bin_dir/'initdb','-D',base/'data','-U','postgres','--auth=trust','--no-locale','--encoding=UTF8'],env,log)
        step([bin_dir/'pg_ctl','-D',base/'data','-l',log,'-o',f'-h 127.0.0.1 -p {port} -k {base}','-w','start'],env,log)

        try:
            yield port
        finally:
            # A cluster that will not stop must not mask the result of the work that ran
            # against it, but it still says why on the way past.
            step([bin_dir/'pg_ctl','-D',base/'data','-m','immediate','-w','stop'],env,log,fatal=False)
