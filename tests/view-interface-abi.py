#!/usr/bin/env python3
"""Compare the two independent declarations of a Qt plugin interface.

A view module and the host that loads it each declare `LogosViewPlugin` and
`LogosViewReplicaFactory` in their own header, and they meet at runtime only
through the IID string:

  module side  logos-plugin-qt/cmake/LogosView{PluginBase,ReplicaFactory}.h.in
  host side    logos-view-module-runtime/include/LogosView{Plugin,ReplicaFactory}.h

They cannot share a header. A module plugin has to compile against Qt alone,
and logos-view-module-runtime depends on logos-plugin-qt, so an include could
only ever point the wrong way. So the copies stay — but a disagreement between
them is silent at every stage: both sides compile, the plugin loads,
`qobject_cast` returns nullptr and the view never appears.

This script makes that disagreement loud. For each pair it extracts, from both
files, the IID string and the ordered list of pure-virtual declarations, and
exits non-zero on any difference. It also fails when it cannot find what it is
looking for, so renaming a class or dropping an IID is a failure rather than a
vacuous pass.
"""

import argparse
import re
import sys


def strip_comments(text):
    """Remove // and /* */ comments without disturbing line structure."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def normalize(decl):
    """Whitespace-insensitive form of a declaration, still readable."""
    decl = re.sub(r"\s+", " ", decl).strip()
    decl = re.sub(r"\s*([*&(),;])\s*", r"\1", decl)
    decl = re.sub(r"([*&])(\w)", r"\1 \2", decl)
    return decl


def class_body(text, name, path):
    """Return the brace-matched body of `class <name> ... { ... }`."""
    head = re.search(r"\bclass\s+" + re.escape(name) + r"\s*(?::[^{;]*)?\{", text)
    if not head:
        sys.exit(
            f"view-interface-abi: no declaration of `class {name}` in {path}.\n"
            f"  The guard compares two copies of this interface; a rename here "
            f"must not turn the comparison into a no-op."
        )
    depth = 0
    start = head.end() - 1
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : i]
    sys.exit(f"view-interface-abi: unbalanced braces in `class {name}` in {path}")


def virtuals(body):
    """Every `virtual ...;` declaration in a class body, in order."""
    return [normalize(m.group(0)) for m in re.finditer(r"\bvirtual\b[^;{}]*;", body)]


def iid(text, name, path):
    m = re.search(
        r"#define\s+" + re.escape(name) + r"_iid\s+\"([^\"]+)\"", text
    )
    if not m:
        sys.exit(
            f"view-interface-abi: no `#define {name}_iid \"...\"` in {path}.\n"
            f"  The IID is the only thing that binds the two copies at runtime; "
            f"it must exist on both sides for this guard to mean anything."
        )
    return m.group(1)


def declare_interface(text, name, path):
    if not re.search(
        r"Q_DECLARE_INTERFACE\s*\(\s*" + re.escape(name) + r"\s*,", text
    ):
        sys.exit(
            f"view-interface-abi: no `Q_DECLARE_INTERFACE({name}, ...)` in {path}"
        )


def read(path, name):
    text = strip_comments(open(path, encoding="utf-8").read())
    declare_interface(text, name, path)
    return {
        "iid": iid(text, name, path),
        "virtuals": virtuals(class_body(text, name, path)),
    }


def compare(name, module_path, host_path):
    mod = read(module_path, name)
    host = read(host_path, name)

    problems = []
    if mod["iid"] != host["iid"]:
        problems.append(
            f"  IID differs — the two sides would never bind at runtime:\n"
            f"    module side ({module_path}): {mod['iid']!r}\n"
            f"    host side   ({host_path}): {host['iid']!r}"
        )
    if mod["virtuals"] != host["virtuals"]:
        lines = ["  pure-virtual surface differs:"]
        for decl in mod["virtuals"]:
            if decl not in host["virtuals"]:
                lines.append(f"    only on the module side: {decl}")
        for decl in host["virtuals"]:
            if decl not in mod["virtuals"]:
                lines.append(f"    only on the host side:   {decl}")
        if len(lines) == 1:  # same set, different order — still an ABI change
            lines.append(f"    module side order: {mod['virtuals']}")
            lines.append(f"    host side order:   {host['virtuals']}")
        problems.append("\n".join(lines))

    if problems:
        print(f"FAIL: {name} has diverged between its two declarations.")
        print(f"  module side: {module_path}")
        print(f"  host side:   {host_path}")
        print("\n".join(problems))
        print(
            "\n  These files are deliberately separate — a module plugin must "
            "build\n  against Qt alone, and the include could only point the "
            "wrong way.\n  Change both, or change neither."
        )
        return False

    print(f"OK: {name} — IID {mod['iid']!r}, {len(mod['virtuals'])} virtuals, "
          f"identical on both sides")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--pair",
        nargs=3,
        action="append",
        metavar=("CLASS", "MODULE_SIDE", "HOST_SIDE"),
        required=True,
    )
    args = ap.parse_args()
    ok = True
    for name, module_path, host_path in args.pair:
        ok = compare(name, module_path, host_path) and ok
    if not ok:
        sys.exit(1)
    print("view-interface-abi: all interface pairs agree")


if __name__ == "__main__":
    main()
