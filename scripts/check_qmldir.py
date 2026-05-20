#!/usr/bin/env python3
"""Verify every component .qml file is registered in its directory's qmldir.

Background:
    Logos QML modules (e.g. the Panels/ and Controls/ subdirs in
    package_manager_ui) use *enumerated* qmldir files — one explicit
    `<Name> <Version> <File>` line per exposed component. Adding a new
    .qml file but forgetting to update the qmldir means the QML engine
    silently refuses to resolve `<Name>` at run time, exploding in the
    ui-host child process and (today) cascading into peer-IPC crashes.

    This script is the cheapest possible static gate against that bug
    class. It only checks "every component file is registered" (and the
    reverse: "every registered name has a backing file"). It does NOT
    type-check QML or resolve cross-module imports — qmllint would,
    but it over-fires on the Logos.* imports the QML engine resolves at
    runtime via Q_ENUM / qmlRegisterType, and tuning it past those
    false positives is more code than the whole check below.

Usage:
    check_qmldir.py <qml_root_dir>

Walks every subdir of <qml_root_dir> that contains a qmldir; for each:
  - Parse the qmldir's `<Name> <Version> <File>` and `internal` entries.
  - List every `*.qml` file in that subdir whose basename starts with
    an uppercase letter (QML convention for a public component).
  - Component file with no qmldir entry  -> error
  - qmldir entry with no backing file    -> error
Exit code is 1 on any mismatch, 0 otherwise. Errors print one per line
with the file:line of the offending qmldir / .qml file for easy IDE jumps.
"""

import os
import re
import sys


_ENTRY_RE = re.compile(
    # Accepts:
    #   `Component 1.0 Component.qml`         — standard
    #   `singleton PackageIcons 1.0 X.qml`    — Qt singleton type
    #   `internal Helper Helper.qml`          — module-private type (no version)
    # The prefix keyword (if any) doesn't affect the file-registration
    # check; we only care that the file appears on some component line.
    r'^(?P<prefix>(?:singleton|internal)\s+)?'
    r'(?P<name>[A-Z][A-Za-z0-9_]*)\s+'
    r'(?:(?P<version>\d+(?:\.\d+)*)\s+)?'
    r'(?P<file>[A-Za-z0-9_]+\.qml)\s*$'
)


def parse_qmldir(path: str) -> tuple[dict[str, int], list[tuple[int, str]]]:
    """Return ({filename: lineno}, [(lineno, raw_line)…]) for component entries.

    Lines we don't recognise (module declaration, plugin lines, prefer
    lines, comments) are silently skipped — only the component-mapping
    lines matter for the registered-vs-on-disk check.
    """
    files_to_line: dict[str, int] = {}
    raw: list[tuple[int, str]] = []
    with open(path, 'r', encoding='utf-8') as f:
        for idx, line in enumerate(f, start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            m = _ENTRY_RE.match(stripped)
            if not m:
                continue
            files_to_line[m.group('file')] = idx
            raw.append((idx, stripped))
    return files_to_line, raw


def component_qmls(dirpath: str) -> list[str]:
    """Component-looking .qml files (basename starts uppercase)."""
    out: list[str] = []
    for entry in os.listdir(dirpath):
        if not entry.endswith('.qml'):
            continue
        # QML convention: components start uppercase. Files that don't
        # are conventionally helpers / privates and need not be exposed.
        if not entry[:1].isupper():
            continue
        out.append(entry)
    return sorted(out)


def check_dir(dirpath: str, qmldir_path: str) -> list[str]:
    errors: list[str] = []
    registered, _ = parse_qmldir(qmldir_path)
    on_disk = set(component_qmls(dirpath))
    registered_files = set(registered)

    for missing in sorted(on_disk - registered_files):
        errors.append(
            f"{qmldir_path}: missing entry for {missing!r} "
            f"(found in {dirpath}/{missing} but not registered)"
        )
    for stale in sorted(registered_files - on_disk):
        errors.append(
            f"{qmldir_path}:{registered[stale]}: stale entry {stale!r} "
            f"(registered but no such file in {dirpath}/)"
        )
    return errors


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <qml_root_dir>", file=sys.stderr)
        return 2
    root = argv[1]
    if not os.path.isdir(root):
        # No QML to check — succeed silently, the module may be C++-only.
        return 0

    any_errors = False
    # Walk recursively: nested module dirs (Controls/, Panels/, …) each
    # carry their own qmldir, and there's no fixed depth.
    for dirpath, dirs, files in os.walk(root):
        # Stable order for reproducible CI output.
        dirs.sort()
        if 'qmldir' not in files:
            continue
        errs = check_dir(dirpath, os.path.join(dirpath, 'qmldir'))
        if errs:
            any_errors = True
            for e in errs:
                print(e, file=sys.stderr)

    if any_errors:
        print(
            "\nqmldir check failed — every component .qml must be "
            "registered in its directory's qmldir (and every qmldir "
            "entry must have a backing file). See the lines above for "
            "the specific mismatches.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
