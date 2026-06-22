#!/usr/bin/env bash
#
# Fetch a fresh copy of the upstream CSC user guide for authoring and reviewing
# skills. Clones (or updates) CSCfi/csc-user-guide into .upstream/ at the repo
# root. The .upstream/ directory is gitignored — it is a local research cache,
# never committed.
#
# Usage: scripts/sync-upstream.sh
#
set -euo pipefail

REPO="https://github.com/CSCfi/csc-user-guide.git"
BRANCH="master"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/.upstream/csc-user-guide"

if [ -d "$DEST/.git" ]; then
  echo "Updating existing checkout at $DEST ..."
  git -C "$DEST" fetch --depth 1 origin "$BRANCH"
  git -C "$DEST" reset --hard "origin/$BRANCH"
  git -C "$DEST" clean -fd
else
  echo "Cloning $REPO into $DEST ..."
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --single-branch --branch "$BRANCH" --no-tags "$REPO" "$DEST"
fi

echo
echo "Upstream docs ready. Source dirs for the current skills:"
echo "  csc-allas -> $DEST/docs/data/Allas"
echo "  csc-pouta -> $DEST/docs/cloud/pouta"
