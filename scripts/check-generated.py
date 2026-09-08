#!/usr/bin/env python3
"""Check generated artifacts without modifying the checkout."""
import filecmp
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
generators = {
    "gen-ports-roster.py": "docs/ports.md",
    "gen-ship-instructions.py": "docs/ship-instructions.md",
    "gen-ux-inventory.py": "docs/ux-inventory.md",
    "gen-game-data.py": "priv/game/catalogue.json",
}
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
print("Generated docs and catalogue match.")
