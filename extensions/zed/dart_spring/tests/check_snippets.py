"""Checks the snippets of snippets/ (dart.json, yaml.json, properties.json):

1. each file is JSON, each snippet has a prefix, a description and a body, and no two snippets of a
   file share a prefix (nor share one with the Dart language server's own snippets);
2. every body parses the way Zed parses snippets: a `$` that starts no tab stop breaks the whole
   snippet, so a Dart or a placeholder `$` must be written `\\$`;
3. every occurrence of a tab stop has the same default text, so that accepting a default fills all
   of them (an occurrence without one would stay empty);
4. yaml.json and properties.json are the same snippets in the two syntaxes: the same prefixes, but
   for those only YAML can say (YAML_ONLY);
5. every Dart snippet, expanded with its defaults, is Dart that `dart format` parses where it is
   meant to be typed (CONTEXTS): at the top of a file, as the member of a class, as a constructor's
   parameter, or as an annotation before a class.

    python3 tests/check_snippets.py            # needs `dart` in PATH
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SNIPPETS = ROOT / "snippets"

# Prefixes of the Dart language server's own snippets, which these must not repeat.
DART_LSP_PREFIXES = {
    "stless", "stful", "stanim", "class", "main", "fun", "for", "forin", "if", "ife",
    "switch", "try", "while", "do", "test", "group",
}

# Where a Dart snippet may be typed: its expansion takes the place of `{}`.
CONTEXTS = (
    "{}",
    "class Snippet {{\n{}\n}}",
    "class Snippet {{\n  Snippet({{{}}});\n}}",
    "{}\nclass Annotated {{}}",
)

# The snippets of yaml.json that properties.json has no counterpart for.
YAML_ONLY = {"spthemeall"}

failures = []


def check(ok, what):
    print(("ok    " if ok else "FAIL  ") + what)
    if not ok:
        failures.append(what)


def parse(body):
    """The tab stops of a snippet `body` (number -> defaults of its occurrences, None for one
    without) and its text expanded with the defaults; raises ValueError where Zed would fail."""
    stops, out, i = {}, [], 0

    def tab_stop(at):
        """Parses the tab stop at `at` (just after `$`): its number, default, and where it ends."""
        if at < len(body) and body[at].isdigit():
            end = at
            while end < len(body) and body[end].isdigit():
                end += 1
            return int(body[at:end]), None, end
        if at < len(body) and body[at] == "{":
            match = re.match(r"\{(\d+)", body[at:])
            if not match:
                raise ValueError(f"`${{` without a number at {at}")
            number, end = int(match.group(1)), at + match.end()
            if body[end] == "}":
                return number, None, end + 1
            if body[end] == "|":
                close = body.index("|}", end + 1)
                return number, body[end + 1:close].split(",")[0], close + 2
            if body[end] != ":":
                raise ValueError(f"`${{{number}` followed by {body[end]!r}")
            default, end = expand(end + 1, closing="}")
            return number, default, end + 1
        raise ValueError(f"a `$` that starts no tab stop at {at - 1}: {body[max(0, at - 10):at + 10]!r}")

    def expand(at, closing=None):
        text = []
        while at < len(body):
            char = body[at]
            if char == "\\" and at + 1 < len(body) and body[at + 1] in "$}\\":
                text.append(body[at + 1])
                at += 2
            elif char == "$":
                number, default, at = tab_stop(at + 1)
                stops.setdefault(number, []).append(default)
                text.append(default or "")
            elif closing and char == closing:
                return "".join(text), at
            else:
                text.append(char)
                at += 1
        if closing:
            raise ValueError(f"a `${{` not closed")
        return "".join(text), at

    text, _ = expand(0)
    return stops, text


def snippets(name):
    return json.loads((SNIPPETS / name).read_text())


def check_file(name):
    print(f"== {name}")
    try:
        found = snippets(name)
    except json.JSONDecodeError as error:
        check(False, f"{name} is JSON: {error}")
        return {}
    shapes = [k for k, v in found.items() if not (isinstance(v.get("prefix"), str) and v.get("description") and isinstance(v.get("body"), list))]
    check(not shapes, f"each snippet has a prefix, a description and a body (a list of lines) {shapes or ''}")
    prefixes = [v["prefix"] for v in found.values()]
    repeated = sorted({p for p in prefixes if prefixes.count(p) > 1})
    check(not repeated, f"no two share a prefix {repeated or ''}")
    clash = sorted(set(prefixes) & DART_LSP_PREFIXES)
    check(not clash, f"none takes a prefix of the Dart language server's snippets {clash or ''}")
    broken, mismatched, expanded = [], [], {}
    for title, snippet in found.items():
        try:
            stops, text = parse("\n".join(snippet["body"]))
        except ValueError as error:
            broken.append(f"{title}: {error}")
            continue
        expanded[title] = text
        for number, defaults in stops.items():
            if len(defaults) > 1 and len(set(defaults)) > 1:
                mismatched.append(f"{title}: ${number} {defaults}")
    check(not broken, f"every body parses as Zed parses snippets {broken or ''}")
    check(not mismatched, f"the occurrences of a tab stop have the same default {mismatched or ''}")
    return expanded


def check_dart(expanded):
    print("== the Dart snippets are Dart")
    dart = shutil.which("dart")
    if not dart:
        check(False, "dart is in PATH")
        return
    unparsed = []
    with tempfile.TemporaryDirectory() as tmp:
        for index, (title, text) in enumerate(expanded.items()):
            for context in CONTEXTS:
                file = Path(tmp) / f"s{index}.dart"
                file.write_text(context.format(text) + "\n")
                result = subprocess.run([dart, "format", "--output=none", str(file)], capture_output=True, text=True)
                if result.returncode == 0:
                    break
            else:
                unparsed.append(title)
    check(not unparsed, f"each parses where it is meant to be typed {unparsed or ''}")


def main():
    dart = check_file("dart.json")
    check_file("yaml.json")
    check_file("properties.json")
    print("== yaml.json and properties.json")
    yaml = {v["prefix"] for v in snippets("yaml.json").values()}
    properties = {v["prefix"] for v in snippets("properties.json").values()}
    check(properties == yaml - YAML_ONLY, f"the same snippets in both syntaxes (only in YAML: {sorted(yaml - properties)}, only in properties: {sorted(properties - yaml)})")
    check_dart(dart)
    print(f"{len(failures)} check(s) failed" if failures else "all checks passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
