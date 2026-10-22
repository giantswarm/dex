#!/usr/bin/env bash
# Mirror upstream into the fork, fast-forward only (FORK.md, "The mirror"):
# `master`, every `v*` branch (`v1`, `v2.46.x`, ...) and every tag upstream
# has. Nothing is ever moved back or deleted. A mirror ref that is not an
# ancestor of its upstream ref was edited, and stops the run.
#
#   scripts/fork/mirror.sh <token> [--check]
#
# The token has to be one that may update workflow files. GITHUB_TOKEN may
# not, not even in a mirrored upstream commit, so the sync passes the App's
# token. Its pushes start upstream's workflows at the mirrored refs, and
# mirror-quiet.sh cancels them. The pushed branch and tag names are written to
# $MIRROR_PUSHED (default mirror-pushed.txt). --check only prints them.
set -euo pipefail
token=$1
mode=${2:-}
here=$(cd "$(dirname "$0")" && pwd)

git fetch -q upstream 'refs/heads/master:refs/remotes/upstream/master' \
  'refs/heads/v*:refs/remotes/upstream/v*' '+refs/tags/*:refs/tags/*'
# Separate fetches: the fork has no `master` before the first mirror run, and a
# fetch that names a missing branch fetches nothing at all.
git fetch -q origin 'refs/heads/master:refs/remotes/origin/master' 2>/dev/null || true
git fetch -q origin 'refs/heads/v*:refs/remotes/origin/v*'

pushed_file=${MIRROR_PUSHED:-mirror-pushed.txt}
: > "$pushed_file"
refspecs=()
names=()
for branch in master $(git for-each-ref --format='%(refname:strip=3)' 'refs/remotes/upstream/v*'); do
  up=$(git rev-parse "refs/remotes/upstream/${branch}")
  if cur=$(git rev-parse -q --verify "refs/remotes/origin/${branch}"); then
    [ "$cur" = "$up" ] && continue
    if ! git merge-base --is-ancestor "$cur" "$up"; then
      echo "::error::origin/${branch} is not an ancestor of upstream/${branch}: the mirror was edited. Restore it by hand (FORK.md, 'The mirror')."
      exit 1
    fi
  fi
  refspecs+=("${up}:refs/heads/${branch}")
  names+=("$branch")
  echo "branch ${branch}: ${cur:-(new)} -> ${up}"
done

# Tags: every upstream tag the fork lacks is copied, and one the fork already
# holds at the same object is current. One the fork holds at ANOTHER object is
# a collision, and stops the run with the tag's name instead of one side
# silently winning. The old fork's own tags (v2.43.2, v2.43.3) look like
# upstream versions, so this can happen.
tags_of() { git ls-remote --tags "$1" | sed -n 's#^\([0-9a-f]*\)[[:space:]]*refs/tags/\([^^]*\)$#\2 \1#p' | sort; }
declare -A fork_tag
while read -r tag sha; do
  [ -n "$tag" ] && fork_tag[$tag]=$sha
done < <(tags_of origin)
while read -r tag sha; do
  [ -n "$tag" ] || continue
  if [ -n "${fork_tag[$tag]:-}" ]; then
    if [ "${fork_tag[$tag]}" != "$sha" ]; then
      echo "::error::tag ${tag} exists in the fork at ${fork_tag[$tag]} and upstream at ${sha}: a tag of ours collides with upstream's. Rename ours first (FORK.md, 'The mirror')."
      exit 1
    fi
    continue
  fi
  refspecs+=("refs/tags/${tag}:refs/tags/${tag}")
  names+=("$tag")
  echo "tag ${tag}: new"
done < <(tags_of upstream)

if [ ${#refspecs[@]} -eq 0 ]; then
  echo "mirror is current"
  exit 0
fi
[ "$mode" = --check ] && exit 0
"${here}/git-push-as.sh" "$token" origin "${refspecs[@]}"
printf '%s\n' "${names[@]}" > "$pushed_file"
