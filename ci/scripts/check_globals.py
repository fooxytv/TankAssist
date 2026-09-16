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



# A file-scope `local NAME = ...` is only in scope *below* itself. Referenced
# above, Lua silently reads a nil global instead -- not a syntax error, not a
# missing global, so neither the parse nor the undeclared-globals pass sees it.
# That is how a `local BORDER_DEFAULT = true` sitting under the function that
# read it shipped a settings default of nil.
#
# Textual rather than AST-based on purpose: the installed luaparser does not
# attach positions to every Name node, and line numbers are the whole point.
# Only column-zero declarations count, so a local inside a function -- scoped to
# that function anyway -- is never considered.
FILE_SCOPE_LOCAL = re.compile(r"^local\s+([A-Za-z_]\w*)\s*=")


def used_before_declared(source: str):
    lines = source.splitlines()

    declared = {}
    for number, line in enumerate(lines, 1):
        match = FILE_SCOPE_LOCAL.match(line)
        if match:
            declared.setdefault(match.group(1), number)

    found = []
    for name, declared_at in declared.items():
        # Not after a "." or ":", so a table field of the same name is not a use
        # of the local.
        word = re.compile(r"(?<![\w.:])" + re.escape(name) + r"(?![\w])")
        for number, line in enumerate(lines[:declared_at - 1], 1):
            if word.search(line.split("--", 1)[0]):
                found.append((name, number, declared_at))
                break
    return sorted(found, key=lambda item: item[1])


def main() -> int:
    allowed = declared_globals() | LUA_BUILTINS
    problems = {}

    sources = []
    for folder in ("core", "ui", "specs", "data"):
        sources.extend(sorted((ROOT / folder).glob("*.lua")))

    scope_problems = {}

    for path in sources:
        source = path.read_text(encoding="utf-8")
        tree = ast.parse(source)
        undeclared = read_names(tree) - bound_names(tree) - field_names(tree) - allowed
        if undeclared:
            problems[path.relative_to(ROOT).as_posix()] = sorted(undeclared)
        early = used_before_declared(source)
        if early:
            scope_problems[path.relative_to(ROOT).as_posix()] = early

    if not problems and not scope_problems:
        print(f"check_globals: {len(sources)} files, no undeclared globals "
              f"or late declarations.")
        return 0

    if problems:
        print("check_globals: undeclared globals (add to .luacheckrc or fix the typo)")
        for filename, names in problems.items():
            print(f"  {filename}: {', '.join(names)}")

    if scope_problems:
        print("check_globals: file-scope locals used above their own declaration")
        print("  (Lua reads these as nil globals -- move the declaration up)")
        for filename, names in scope_problems.items():
            for name, line, declared_at in names:
                print(f"  {filename}:{line}: {name} (declared at line {declared_at})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
