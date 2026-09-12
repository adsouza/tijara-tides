#!/usr/bin/env python3
"""Fail before pushing if `mix gettext.merge` pruned a runtime-dispatched translation.

Most text reaches Gettext through a literal `gettext("...")` call, so `mix
gettext.extract` finds it and writes it to default.pot. Some does not:
`l10n(value)` dispatches through Localization.Names.translate/1, falls through
Localization.Ports.translate/1, and ends at Localization.text(value) —
`Gettext.gettext(Backend, value)` with a *dynamic* argument. The extractor
cannot see those strings, so they never reach the .pot, yet they resolve
correctly against a locale catalogue at run time.

`mix gettext.merge` reads "absent from the .pot" as "obsolete" and deletes
them. Nothing crashes; the label simply renders in English from then on. Run
`mix gettext.extract` alone, which is all `mix precommit` gates on.

This guards the strings listed in priv/gettext/runtime-msgids.txt, and keeps
that manifest honest in both directions.
"""

import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
pot_path = root / "priv/gettext/default.pot"
manifest_path = root / "priv/gettext/runtime-msgids.txt"
locale_paths = sorted((root / "priv/gettext").glob("*/LC_MESSAGES/default.po"))

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}


def unescape(text):
    out, index = [], 0
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            out.append(ESCAPES.get(text[index + 1], text[index + 1]))
            index += 2
        else:
            out.append(char)
            index += 1
    return "".join(out)


def parse(path):
    """Map each msgid to whether the entry carries a non-empty translation."""
    entries, msgid, translated, field = {}, None, False, None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("#~"):  # obsolete; already out of service
            continue
        if line.startswith("#") or not line:
            continue
        if match := re.match(r'^(msgid|msgid_plural|msgstr(?:\[\d+\])?)\s+"(.*)"$', line):
            keyword, value = match[1], unescape(match[2])
            if keyword == "msgid":
                if msgid is not None:
                    entries[msgid] = translated
                msgid, translated = value, False
                field = "msgid"
            elif keyword == "msgid_plural":
                field = "other"
            else:
                translated = translated or bool(value)
                field = "msgstr"
        elif match := re.match(r'^"(.*)"$', line):  # continuation of the line above
            value = unescape(match[1])
            if field == "msgid":
                msgid += value
            elif field == "msgstr":
                translated = translated or bool(value)
    if msgid is not None:
        entries[msgid] = translated
    entries.pop("", None)  # the catalogue header, not a message
    return entries


def literals_in_source():
    sources = [p for p in (root / "lib").rglob("*") if p.suffix in {".ex", ".exs", ".heex"}]
    return "\n".join(p.read_text(encoding="utf-8") for p in sources)


def quoted(msgid):
    return msgid.replace("\\", "\\\\").replace('"', '\\"')


if not manifest_path.exists():
    raise SystemExit(f"Missing {manifest_path.relative_to(root)}; it lists the msgids that only run-time dispatch can reach.")

manifest = [
    line.strip()
    for line in manifest_path.read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.startswith("#")
]
if not manifest:
    raise SystemExit(f"{manifest_path.relative_to(root)} is empty; an emptied manifest would guard nothing.")

pot = parse(pot_path)
source = literals_in_source()
problems = []

# A guarded msgid that lib/ never mentions is a manifest error, not a lost
# translation. Settle that first so the diagnosis below stays accurate.
stale = [m for m in manifest if f'"{quoted(m)}"' not in source]
live = [m for m in manifest if m not in stale]

# 1. The point of this script: merge deletes exactly these.
for locale_path in locale_paths:
    catalogue = parse(locale_path)
    lost = [m for m in live if not catalogue.get(m)]
    if lost:
        listed = "\n".join(f'  - "{m}"' for m in lost)
        problems.append(
            f"{locale_path.relative_to(root)} has no translation for these "
            f"runtime-dispatched msgids:\n{listed}\n"
            f"  If they were translated before, this is the signature of "
            f"`mix gettext.merge`: restore the file (git checkout) and run only "
            f"`mix gettext.extract`. If the label is new, translate it there by hand — "
            f"extraction will never add it for you."
        )

# 2. A manifest entry nothing references any more is rot; retire it deliberately.
if stale:
    problems.append(
        "These msgids are guarded but no longer appear in lib/:\n"
        + "\n".join(f'  - "{m}"' for m in stale)
        + f"\n  Drop them from {manifest_path.relative_to(root)}, then prune them from the catalogues."
    )

# 3. Once a string becomes a literal gettext(...) call the extractor protects it.
if extracted := [m for m in manifest if m in pot]:
    problems.append(
        "These msgids now reach default.pot on their own:\n"
        + "\n".join(f'  - "{m}"' for m in extracted)
        + f"\n  Drop them from {manifest_path.relative_to(root)}; extraction already covers them."
    )

# 4. Anything outside both sets is unaccounted for — guard it or prune it.
for locale_path in locale_paths:
    unexplained = sorted(set(parse(locale_path)) - set(pot) - set(manifest))
    if unexplained:
        problems.append(
            f"{locale_path.relative_to(root)} holds msgids that are in neither "
            f"default.pot nor the manifest:\n"
            + "\n".join(f'  - "{m}"' for m in unexplained)
            + f"\n  Add each to {manifest_path.relative_to(root)} if run-time dispatch "
            f"reaches it, or delete it from the catalogue if it is dead."
        )

if problems:
    print("\n\n".join(problems), file=sys.stderr)
    raise SystemExit("Gettext catalogue check failed.")

catalogues = ", ".join(p.parent.parent.name for p in locale_paths)
print(f"Gettext catalogues agree: {len(manifest)} runtime-dispatched msgids translated in {catalogues}.")
