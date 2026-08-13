#!/usr/bin/env python3
"""Find global reads that .luacheckrc does not declare.

luacheck is the real gate, but it only runs in the CI container. This is a
close-enough approximation that runs anywhere Python and luaparser are
available, so a mistyped API name is caught before a push rather than in game.

Deliberately over-approximates what counts as declared: a name bound as a local,
parameter or loop variable *anywhere in the file* is treated as declared
everywhere in it. That means real shadowing cases are not reported, but a name
that is never bound at all -- GetSepllInfo -- still is, which is the case worth
catching.

Exit code 1 if anything is undeclared.
"""

import re
import sys
from pathlib import Path

from luaparser import ast, astnodes

ROOT = Path(__file__).resolve().parents[2]

LUA_BUILTINS = {
    "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable",
    "ipairs", "load", "loadfile", "loadstring", "module", "next", "pairs",
    "pcall", "print", "rawequal", "rawget", "rawlen", "rawset", "require",
    "select", "setfenv", "setmetatable", "tonumber", "tostring", "type",
    "unpack", "xpcall", "coroutine", "debug", "io", "math", "os", "package",
    "string", "table", "bit", "_G", "_VERSION", "self", "arg",
}


def declared_globals() -> set:
    """Names listed in .luacheckrc's globals / read_globals tables."""
    text = (ROOT / ".luacheckrc").read_text(encoding="utf-8")
    names = set()
    for block in re.findall(r"(?:read_globals|globals)\s*=\s*\{(.*?)\n\}", text, re.S):
        names.update(re.findall(r'"([^"]+)"', block))
    return names


def bound_names(tree) -> set:
    """Every name bound as a local, parameter or loop variable in this tree."""
    names = set()
    for node in ast.walk(tree):
        targets = []
        if isinstance(node, astnodes.LocalAssign):
            targets = node.targets or []
        elif isinstance(node, astnodes.Forin):
            targets = node.targets or []
        elif isinstance(node, astnodes.Fornum):
            targets = [node.target]
        elif isinstance(node, (astnodes.Function, astnodes.LocalFunction,
                               astnodes.Method, astnodes.AnonymousFunction)):
            targets = list(node.args or [])
            name = getattr(node, "name", None)
            if isinstance(name, astnodes.Name):
                targets.append(name)

        for target in targets:
            if isinstance(target, astnodes.Name):
                names.add(target.id)
    return names


def read_names(tree) -> set:
    """Every bare identifier, minus the field half of a.b and the key of {a=1}."""
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, astnodes.Index):
            # In a.b, `b` is a field rather than a global.
            if isinstance(node.idx, astnodes.Name):
                continue
        if isinstance(node, astnodes.Name):
            names.add(node.id)
    return names


def field_names(tree) -> set:
    """Identifiers that are a field or method name rather than a global.

    Covers `a.b`, the `b` in `{ b = 1 }`, and the method half of both `a:b()`
    and `function a:b() end` -- without the last two every widget call in the
    addon reads as an undeclared global.
    """
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, astnodes.Index) and isinstance(node.idx, astnodes.Name):
            names.add(node.idx.id)
        elif isinstance(node, astnodes.Field) and isinstance(node.key, astnodes.Name):
            names.add(node.key.id)
        elif isinstance(node, astnodes.Invoke) and isinstance(node.func, astnodes.Name):
            names.add(node.func.id)
        elif isinstance(node, astnodes.Method) and isinstance(node.name, astnodes.Name):
            names.add(node.name.id)
    return names


def main() -> int:
    allowed = declared_globals() | LUA_BUILTINS
    problems = {}

    sources = []
    for folder in ("core", "ui", "specs", "data"):
        sources.extend(sorted((ROOT / folder).glob("*.lua")))

    for path in sources:
        tree = ast.parse(path.read_text(encoding="utf-8"))
        undeclared = read_names(tree) - bound_names(tree) - field_names(tree) - allowed
        if undeclared:
            problems[path.relative_to(ROOT).as_posix()] = sorted(undeclared)

    if not problems:
        print(f"check_globals: {len(sources)} files, no undeclared globals.")
        return 0

    print("check_globals: undeclared globals (add to .luacheckrc or fix the typo)")
    for filename, names in problems.items():
        print(f"  {filename}: {', '.join(names)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
