#!/usr/bin/env python3
"""Fail when an AppStream launchable does not name the installed .desktop file."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

metadata, expected = Path(sys.argv[1]), sys.argv[2]
launchables = ET.parse(metadata).findall("launchable[@type='desktop-id']")
declared = [launchable.text for launchable in launchables]
if declared != [expected]:
    raise SystemExit(
        f"{metadata}: AppStream desktop-id {declared} must name the installed "
        f"launcher {expected!r}"
    )
