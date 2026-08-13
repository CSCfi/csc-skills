#!/usr/bin/env bash
#
# Validate this repo against the Agent Skills spec and its own layout rules:
#
#   - every skills/<name>/SKILL.md has parseable frontmatter
#   - `name` matches the directory and the spec's charset rules (max 64)
#   - `description` is non-empty and at most 1024 characters
#     (https://agentskills.io/specification)
#   - both plugin manifests are valid JSON
#   - AGENTS.md and .agents/skills/* symlinks resolve, one per skill
#
# Usage: scripts/check-skills.sh   (exits non-zero on any failure)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
note() { printf '%-7s %s\n' "$1" "$2"; }

# --- SKILL.md frontmatter -----------------------------------------------------
while IFS= read -r skill; do
  name="$(basename "$skill")"
  if [ ! -f "$skill/SKILL.md" ]; then
    note FAIL "$name: no SKILL.md"; fail=1; continue
  fi
  if ! out="$(python3 "$ROOT/scripts/lib/skillmeta.py" "$skill/SKILL.md" "$name" 2>&1)"; then
    note FAIL "$name: $out"; fail=1; continue
  fi
  note ok "$name: $out"
done < <(find skills -mindepth 1 -maxdepth 1 -type d | sort)

# --- plugin manifests ---------------------------------------------------------
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         .codex-plugin/plugin.json; do
  if [ ! -f "$f" ]; then
    note FAIL "$f: missing"; fail=1
  elif python3 -m json.tool "$f" >/dev/null 2>&1; then
    note ok "$f: valid JSON"
  else
    note FAIL "$f: invalid JSON"; fail=1
  fi
done

# --- symlinks -----------------------------------------------------------------
for link in AGENTS.md; do
  if [ -L "$link" ] && [ -e "$link" ]; then
    note ok "$link -> $(readlink "$link")"
  else
    note FAIL "$link: missing or broken symlink"; fail=1
  fi
done

while IFS= read -r skill; do
  name="$(basename "$skill")"
  link=".agents/skills/$name"
  if [ -L "$link" ] && [ -e "$link" ]; then
    note ok "$link -> $(readlink "$link")"
  else
    note FAIL "$link: missing or broken symlink"; fail=1
  fi
done < <(find skills -mindepth 1 -maxdepth 1 -type d | sort)

echo
if [ "$fail" -ne 0 ]; then
  echo "FAILED — see above."
  exit 1
fi
echo "All checks passed."
