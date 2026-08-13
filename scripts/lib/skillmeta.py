#!/usr/bin/env python3
"""Check one SKILL.md's frontmatter against the Agent Skills spec.

Usage: skillmeta.py <path/to/SKILL.md> <expected-name>

Prints a one-line summary on success; prints the problem and exits 1 on
failure. Deliberately dependency-free (no PyYAML) so it runs anywhere: it
parses only the small subset of YAML these files use.
"""
import re
import sys

NAME_MAX = 64
DESC_MAX = 1024  # https://agentskills.io/specification


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        raise ValueError("no YAML frontmatter delimited by ---")
    return m.group(1)


def scalar(fm, key):
    """Read `key` as a plain, folded (>) or literal (|) scalar."""
    m = re.search(rf"^{key}:[ \t]*(\S?)[^\n]*\n?", fm, re.M)
    if not m:
        raise ValueError(f"no `{key}:` field")
    style = m.group(1)
    if style in (">", "|"):
        body = fm[m.end():]
        lines = []
        for line in body.splitlines():
            if line.strip() and not line.startswith((" ", "\t")):
                break  # dedented: next key
            lines.append(line.strip())
        if style == ">":
            # folded: single newlines become spaces; clip chomping keeps one \n
            value = " ".join(l for l in lines if l) + "\n"
        else:
            value = "\n".join(lines).rstrip("\n") + "\n"
    else:
        value = re.match(rf"^{key}:[ \t]*(.*)$", m.group(0).rstrip("\n")).group(1)
        value = value.strip().strip("'\"")
    return value


def main():
    path, expected = sys.argv[1], sys.argv[2]
    try:
        fm = frontmatter(open(path, encoding="utf-8").read())
        name = scalar(fm, "name").strip()
        desc = scalar(fm, "description")
    except (OSError, ValueError) as e:
        print(e)
        return 1

    problems = []
    if name != expected:
        problems.append(f"name {name!r} != directory {expected!r}")
    if not 1 <= len(name) <= NAME_MAX:
        problems.append(f"name must be 1-{NAME_MAX} chars (is {len(name)})")
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name):
        problems.append(
            f"name {name!r} must be lowercase alphanumeric/hyphen, with no "
            "leading, trailing or consecutive hyphens"
        )
    if not desc.strip():
        problems.append("description is empty")
    if len(desc) > DESC_MAX:
        problems.append(
            f"description is {len(desc)} chars, over the {DESC_MAX} limit "
            f"by {len(desc) - DESC_MAX}"
        )

    if problems:
        print("; ".join(problems))
        return 1

    print(f"name ok, description {len(desc)}/{DESC_MAX} chars")
    return 0


if __name__ == "__main__":
    sys.exit(main())
