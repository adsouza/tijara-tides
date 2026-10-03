#!/usr/bin/env python3
"""Check generated artifacts without modifying the checkout."""
import argparse
import filecmp
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--docs-only', action='store_true', help='Check generated Markdown without rebuilding the runtime catalogue.')
args = parser.parse_args()
generators = {
    "gen-ports-roster.py": "docs/ports.md",
    "gen-ship-instructions.py": "docs/ship-instructions.md",
    "gen-ux-inventory.py": "docs/ux-inventory.md",
}
if not args.docs_only:
    generators["gen-game-data.py"] = "priv/game/catalogue.json"
with tempfile.TemporaryDirectory(prefix="tijara-generated-") as directory:
    target = Path(directory)
    shutil.copytree(root / "scripts", target / "scripts")
    shutil.copytree(root / "docs", target / "docs")
    (target / "priv/game").mkdir(parents=True)
    stale = []
    for generator, artifact in generators.items():
        subprocess.run([sys.executable, str(target / "scripts" / generator)], check=True, cwd=target)
        if not filecmp.cmp(root / artifact, target / artifact, shallow=False):
            stale.append(f"{artifact}: regenerate with scripts/{generator}")
    if stale:
        raise SystemExit("Generated files are stale:\n" + "\n".join(stale))
print("Generated docs match." if args.docs_only else "Generated docs and catalogue match.")
