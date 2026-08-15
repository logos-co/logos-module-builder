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

WHAT BINDS THE TWO SIDES, and therefore what this script compares
-----------------------------------------------------------------
Three separate strings have to line up, not one, and they live in three
different places:

  1. `#define <Name>_iid "..."`            — the literal, on both sides.
  2. `Q_DECLARE_INTERFACE(<Name>, <iid>)`  — what `qobject_cast<Name*>` on the
     HOST compares against. Its argument is resolved through the #defines,
     because `Q_DECLARE_INTERFACE(X, "literal")` is just as legal as
     `Q_DECLARE_INTERFACE(X, X_iid)` and only the resolved value matters.
  3. `Q_PLUGIN_METADATA(IID <iid>)` on the CONCRETE plugin class — what
     `QPluginLoader` reads out of the built binary, and the one an earlier
     version of this guard never looked at. Together with `Q_INTERFACES(...)`
     on that same class it is the entire runtime binding; the abstract class
     above it is only a compile-time shape.

An earlier version of this script read (1) and the `virtual ...;` list inside
`class <Name>`, and nothing else. Both of the mutations that actually break a
running view land outside that window and it stayed green through both:

    Q_PLUGIN_METADATA(IID LogosViewReplicaFactory_iid)
  → Q_PLUGIN_METADATA(IID "logos.view.replica_factory/2.0")
        the built plugin advertises /2.0 while the host looks for /1.0

    Q_INTERFACES(LogosViewReplicaFactory)  deleted
        moc emits no qt_metacast entry, qobject_cast returns nullptr

So the concrete classes are inspected too. For each class in the module-side
file that names the interface in its base clause, this script checks that it
still declares the interface to moc (`Q_INTERFACES`), that it is still a moc
class at all when it derives from QObject (`Q_OBJECT`), and that whatever IID
it exports through `Q_PLUGIN_METADATA` resolves to the IID the host casts on.

It also fails when it cannot find what it is looking for — a renamed class, a
missing `#define`, a base class dropped from the interface, or a module-side
file that no longer implements the interface it declares — so that erasing the
subject of a comparison is a failure rather than a vacuous pass.
"""

import argparse
import re
import sys

# A type name in these headers may be a CMake placeholder — the module side is
# a configure_file() template, so `@LOGOS_FACTORY_CLASS@` and
# `@LOGOS_REP_CLASS@ViewPluginBase` are class names here.
TOKEN = r"[A-Za-z_@][A-Za-z0-9_@]*"


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


def fail(msg):
    sys.exit("view-interface-abi: " + msg)


def match_brace(text, open_index, path):
    """Return the body between `text[open_index] == '{'` and its match."""
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_index + 1 : i]
    fail(f"unbalanced braces starting at offset {open_index} in {path}")


def parse_bases(clause):
    """Base type names from a `: public A, private B` clause."""
    if not clause:
        return []
    bases = []
    for part in clause.split(","):
        part = re.sub(r"\b(public|protected|private|virtual)\b", " ", part)
        names = re.findall(TOKEN, part)
        if names:
            bases.append(names[-1])
    return bases


def parse_classes(text, path):
    """Every `class/struct <name> [: bases] { ... }` definition in the file.

    Forward declarations (`class QObject;`) are skipped: the `[^{;]*` in the
    head pattern refuses to cross a semicolon.
    """
    classes = []
    for head in re.finditer(
        r"\b(?:class|struct)\s+(" + TOKEN + r")\s*(?::([^{;]*))?\{", text
    ):
        body = match_brace(text, head.end() - 1, path)
        classes.append(
            {
                "name": head.group(1),
                "bases": parse_bases(head.group(2)),
                "body": body,
            }
        )
    return classes


def parse_defines(text):
    """`#define NAME "literal"` map, used to resolve IID arguments."""
    return {
        m.group(1): m.group(2)
        for m in re.finditer(
            r"#define\s+(" + TOKEN + r")\s+\"([^\"]*)\"", text
        )
    }


def resolve_iid(expr, defines, where, path):
    """An IID argument is either a string literal or a macro naming one."""
    expr = expr.strip()
    literal = re.fullmatch(r"\"([^\"]*)\"", expr)
    if literal:
        return literal.group(1)
    if expr in defines:
        return defines[expr]
    fail(
        f"cannot resolve the IID `{expr}` used by {where} in {path}.\n"
        f"  It is neither a string literal nor a `#define` in this file, so "
        f"this guard cannot tell what the binary will advertise. Spell the "
        f"IID as a literal or define it here."
    )


def macro_arg(body, macro):
    """The raw argument text of `MACRO(...)` inside a class body, or None."""
    m = re.search(re.escape(macro) + r"\s*\(([^)]*)\)", body)
    return m.group(1) if m else None


def read(path, name):
    """Everything this guard knows how to compare, from one file."""
    text = strip_comments(open(path, encoding="utf-8").read())
    defines = parse_defines(text)
    classes = parse_classes(text, path)

    iface = next((c for c in classes if c["name"] == name), None)
    if iface is None:
        fail(
            f"no declaration of `class {name}` in {path}.\n"
            f"  The guard compares two copies of this interface; a rename here "
            f"must not turn the comparison into a no-op."
        )

    define_key = name + "_iid"
    if define_key not in defines:
        fail(
            f"no `#define {define_key} \"...\"` in {path}.\n"
            f"  The IID is the only thing that binds the two copies at "
            f"runtime; it must exist on both sides for this guard to mean "
            f"anything."
        )

    decl = re.search(
        r"Q_DECLARE_INTERFACE\s*\(\s*" + re.escape(name) + r"\s*,([^)]*)\)",
        text,
    )
    if not decl:
        fail(f"no `Q_DECLARE_INTERFACE({name}, ...)` in {path}")

    # Classes that implement the interface. The abstract class is only a
    # compile-time shape; these are where the runtime binding is declared.
    implementors = []
    for c in classes:
        if c["name"] == name or name not in c["bases"]:
            continue
        plugin_arg = macro_arg(c["body"], "Q_PLUGIN_METADATA")
        plugin_iid = None
        if plugin_arg is not None:
            iid_expr = re.match(r"\s*IID\s+(\"[^\"]*\"|" + TOKEN + r")", plugin_arg)
            if not iid_expr:
                fail(
                    f"`Q_PLUGIN_METADATA({plugin_arg.strip()})` on class "
                    f"{c['name']} in {path} has no IID argument.\n"
                    f"  QPluginLoader reads that IID; without it the plugin "
                    f"cannot bind to {name}."
                )
            plugin_iid = resolve_iid(
                iid_expr.group(1),
                defines,
                f"Q_PLUGIN_METADATA on class {c['name']}",
                path,
            )
        q_interfaces_arg = macro_arg(c["body"], "Q_INTERFACES")
        implementors.append(
            {
                "name": c["name"],
                "bases": c["bases"],
                "q_object": re.search(r"\bQ_OBJECT\b", c["body"]) is not None,
                "plugin_iid": plugin_iid,
                "has_plugin_metadata": plugin_arg is not None,
                # Q_INTERFACES takes a whitespace-separated list, e.g.
                # `Q_INTERFACES(FooInterface LogosViewPlugin)`.
                "interfaces": (
                    re.findall(TOKEN, q_interfaces_arg)
                    if q_interfaces_arg is not None
                    else None
                ),
            }
        )

    return {
        "path": path,
        "iid_define": defines[define_key],
        "declared_iid": resolve_iid(
            decl.group(1), defines, f"Q_DECLARE_INTERFACE({name}, ...)", path
        ),
        "bases": iface["bases"],
        "virtuals": [
            normalize(m.group(0))
            for m in re.finditer(r"\bvirtual\b[^;{}]*;", iface["body"])
        ],
        "implementors": implementors,
    }


def check_implementors(name, side, authoritative_iid, problems):
    """The runtime binding, per concrete class. This is the window the

    previous version of the guard did not have, and where both known
    escaping mutations lived.
    """
    for impl in side["implementors"]:
        who = f"class {impl['name']} in {side['path']}"

        # Deriving from QObject without Q_OBJECT means moc emits no
        # metaobject at all — no qt_metacast, so no qobject_cast.
        if "QObject" in impl["bases"] and not impl["q_object"]:
            problems.append(
                f"  {who} derives from QObject but has no Q_OBJECT — moc "
                f"generates no metaobject, so qobject_cast<{name}*> can "
                f"never succeed."
            )

        if impl["has_plugin_metadata"] and not impl["q_object"]:
            problems.append(
                f"  {who} has Q_PLUGIN_METADATA but no Q_OBJECT; moc will "
                f"not emit the plugin metadata."
            )

        # Q_INTERFACES is what makes moc emit the qt_metacast branch that
        # qobject_cast<Name*> walks. A class that inherits the interface but
        # does not declare it to moc casts to nullptr — a blank view.
        # A non-QObject implementor (a plain base like *ViewPluginBase) has
        # no metaobject to declare it in, and needs none.
        if impl["q_object"]:
            if impl["interfaces"] is None:
                problems.append(
                    f"  {who} implements {name} and is a QObject, but "
                    f"declares no Q_INTERFACES — moc emits no qt_metacast "
                    f"entry for {name}, so qobject_cast<{name}*> returns "
                    f"nullptr and the view never appears."
                )
            elif name not in impl["interfaces"]:
                problems.append(
                    f"  {who} lists Q_INTERFACES("
                    f"{' '.join(impl['interfaces'])}) — {name} is missing "
                    f"from it, so qobject_cast<{name}*> returns nullptr."
                )

        # The IID baked into the binary, versus the one the host casts on.
        if impl["plugin_iid"] is not None and impl["plugin_iid"] != authoritative_iid:
            problems.append(
                f"  {who} exports Q_PLUGIN_METADATA IID "
                f"{impl['plugin_iid']!r}, but the interface is bound at "
                f"{authoritative_iid!r}.\n"
                f"    QPluginLoader reads the exported IID; the two would "
                f"never meet."
            )


def compare(name, module_path, host_path):
    mod = read(module_path, name)
    host = read(host_path, name)

    problems = []

    if mod["iid_define"] != host["iid_define"]:
        problems.append(
            f"  `#define {name}_iid` differs — the two sides would never "
            f"bind at runtime:\n"
            f"    module side ({module_path}): {mod['iid_define']!r}\n"
            f"    host side   ({host_path}): {host['iid_define']!r}"
        )

    # Q_DECLARE_INTERFACE is resolved, not merely present: its argument is
    # what qobject_cast compares, and it does not have to be the #define.
    if mod["declared_iid"] != host["declared_iid"]:
        problems.append(
            f"  `Q_DECLARE_INTERFACE({name}, ...)` resolves differently:\n"
            f"    module side ({module_path}): {mod['declared_iid']!r}\n"
            f"    host side   ({host_path}): {host['declared_iid']!r}"
        )
    for side in (mod, host):
        if side["declared_iid"] != side["iid_define"]:
            problems.append(
                f"  in {side['path']}, `Q_DECLARE_INTERFACE({name}, ...)` "
                f"resolves to {side['declared_iid']!r} but "
                f"`#define {name}_iid` is {side['iid_define']!r} — the file "
                f"disagrees with itself."
            )

    # The interface's own base list is part of its vtable layout.
    if mod["bases"] != host["bases"]:
        problems.append(
            f"  `class {name}` has a different base list, which changes the "
            f"vtable layout:\n"
            f"    module side ({module_path}): {mod['bases'] or '(none)'}\n"
            f"    host side   ({host_path}): {host['bases'] or '(none)'}"
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

    # The module-side file exists to implement this interface. If nothing in
    # it derives from the interface any more, a base class was dropped or the
    # interface was renamed out from under the concrete class — and every
    # check below would otherwise pass vacuously.
    if not mod["implementors"]:
        problems.append(
            f"  no class in {module_path} derives from {name}.\n"
            f"    That file is the module side of the interface; if nothing "
            f"implements it, the concrete-class checks below have no subject "
            f"and a real divergence would pass unnoticed."
        )

    # The host's Q_DECLARE_INTERFACE is the authority: it is the string
    # qobject_cast and QPluginLoader compare against in the host process.
    check_implementors(name, mod, host["declared_iid"], problems)
    check_implementors(name, host, host["declared_iid"], problems)

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

    print(f"OK: {name} — IID {mod['iid_define']!r}, {len(mod['virtuals'])} virtuals")
    for impl in mod["implementors"]:
        exported = (
            f"Q_PLUGIN_METADATA IID {impl['plugin_iid']!r}"
            if impl["plugin_iid"] is not None
            else "no Q_PLUGIN_METADATA (not a plugin root)"
        )
        declared = (
            " ".join(impl["interfaces"])
            if impl["interfaces"] is not None
            else "(not a QObject)"
        )
        print(
            f"      module-side implementor {impl['name']}: {exported}, "
            f"Q_INTERFACES({declared})"
        )
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
