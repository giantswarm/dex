#!/usr/bin/env bash
# The release tag for the head of the consumed branch (FORK.md, "Release
# scheme"): the upstream release it sits on plus the next free -gs.N.
#
#   scripts/fork/next-release.sh [<commit>]
#
# Prints `tag=<vX.Y.Z-gs.N>` when the commit needs a release, or `skip=<reason>`
# when it is already tagged, or when nothing that goes into the image changed
# since the line's last release. Every release tag must be in the local clone.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/fork/releases.sh
. "${here}/releases.sh"

head=$(git rev-parse "${1:-HEAD}^{commit}")
pin_tag=$(pinned_release "$head")

own=$(git tag --points-at "$head" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-gs\.[0-9]+$' || true)
if [ -n "$own" ]; then
  echo "skip=$(git rev-parse --short=7 "$head") is already released as ${own//$'\n'/ }"
  exit 0
fi

# Our releases on this upstream release, by their number N.
last_n=$(git tag -l "${pin_tag}-gs.*" | sed -nE "s/^${pin_tag//./\\.}-gs\.([0-9]+)$/\1/p" | sort -n | tail -n 1)

# Docs, workflows and the fork's own scripts don't go into the image.
if [ -n "$last_n" ] && git diff --quiet "${pin_tag}-gs.${last_n}" "$head" -- . \
    ':(exclude,glob)**/*.md' ':(exclude).github' ':(exclude)scripts/fork'; then
  echo "skip=nothing that goes into the image changed since ${pin_tag}-gs.${last_n}"
  exit 0
fi

echo "tag=${pin_tag}-gs.$(( ${last_n:-0} + 1 ))"
