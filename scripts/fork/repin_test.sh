#!/usr/bin/env bash
# Tests for repin.sh. Each test builds throwaway repositories in a temporary
# directory: `upstream` with release tags, `origin` with the consumed branch,
# and a clone of origin to run repin.sh in.
#
#   scripts/fork/repin_test.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

failed=0
fail() { echo "FAIL: $*" >&2; failed=1; }

commit_file() { # commit_file <file> <content> <message>
  printf '%s\n' "$2" > "$1"
  git add "$1"
  git commit -q -m "$3"
}

# Upstream releases a change that the consumed branch already carries as an
# unchanged copy: go.mod goes v0.49 -> v0.50 -> v0.52 in two commits, both in
# the new release. The re-pin must drop both copies and keep our own patch.
# Before the fix, the copy of the first commit conflicted with the release.
test_drops_carried_commits_that_the_release_contains() {
  local tmp
  tmp=$(mktemp -d)
  trap 'cd /; rm -rf "$tmp"' RETURN

  # Arrange
  setup_released_copies "$tmp"

  # Act
  local status
  status=$(run_repin "$tmp")

  # Assert
  [ "$status" -eq 0 ] || fail "repin.sh exited $status, want 0: $(cat "$tmp/out" "$tmp/report.md" 2>/dev/null)"
  grep -qx 'status=rebased' "$tmp/report.env" || fail "want status=rebased in report.env: $(cat "$tmp/report.env")"
  local replayed
  replayed=$(git -C "$tmp/work" log --format=%s v1.0.1..sync/test 2> /dev/null || true)
  [ "$replayed" = 'feat: our patch' ] || fail "want only 'feat: our patch' on top of v1.0.1, got: ${replayed:-nothing}"
  grep -q 'merged upstream as' "$tmp/report.md" || fail "want the report to name the dropped copies as merged upstream"
}

# Builds upstream (v1.0.0, then v1.0.1 = two go.mod bumps), origin with the
# consumed branch giantswarm = v1.0.0 + our patch + copies of both bumps +
# whatever the caller adds in "$tmp/seed", and a clone in "$tmp/work".
setup_released_copies() { # setup_released_copies <tmp> <extra commands for the seed>
  local tmp=$1 extra=${2:-true}
  git init -q -b master "$tmp/upstream"
  (
    cd "$tmp/upstream"
    commit_file go.mod 'tools v0.49' 'initial'
    git tag v1.0.0
    commit_file go.mod 'tools v0.50' 'bump tools to v0.50'
    commit_file go.mod 'tools v0.52' 'bump tools to v0.52'
    git tag v1.0.1
  )
  git clone -q "$tmp/upstream" "$tmp/seed"
  (
    cd "$tmp/seed"
    git switch -q -c giantswarm v1.0.0
    commit_file ours.txt 'our patch' 'feat: our patch'
    git cherry-pick v1.0.0..v1.0.1 > /dev/null
    eval "$extra"
  )
  git clone -q --bare "$tmp/seed" "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/work"
  git -C "$tmp/work" remote add upstream "$tmp/upstream"
}

run_repin() { # run_repin <tmp>: runs repin.sh in "$tmp/work", prints its exit code
  local status=0
  (cd "$1/work" && UPSTREAM_REF=v1.0.1 CANDIDATE=sync/test REPORT="$1/report.md" REPORT_ENV="$1/report.env" \
    "$here/repin.sh" > "$1/out" 2>&1) || status=$?
  echo "$status"
}

# Git computes no patch id for a commit without changes. An empty carried
# commit must be replayed like any other, not break the lookup by patch id.
test_keeps_an_empty_carried_commit() {
  local tmp
  tmp=$(mktemp -d)
  trap 'cd /; rm -rf "$tmp"' RETURN

  # Arrange
  setup_released_copies "$tmp" "git commit -q --allow-empty -m 'chore: empty marker'"

  # Act
  local status
  status=$(run_repin "$tmp")

  # Assert
  [ "$status" -eq 0 ] || fail "empty commit: repin.sh exited $status, want 0: $(cat "$tmp/out")"
  local replayed
  replayed=$(git -C "$tmp/work" log --format=%s v1.0.1..sync/test 2> /dev/null | tr '\n' '|' || true)
  [ "$replayed" = 'chore: empty marker|feat: our patch|' ] || fail "empty commit: want our patch and the empty marker on top of v1.0.1, got: ${replayed:-nothing}"
}

# With rebase.abbreviateCommands, git writes `p` instead of `pick` in the todo
# list. Someone running a manual re-pin may have it set.
test_drops_released_commits_with_abbreviated_commands() {
  local tmp
  tmp=$(mktemp -d)
  trap 'cd /; rm -rf "$tmp"' RETURN

  # Arrange
  setup_released_copies "$tmp"
  git -C "$tmp/work" config rebase.abbreviateCommands true

  # Act
  local status
  status=$(run_repin "$tmp")

  # Assert
  [ "$status" -eq 0 ] || fail "abbreviateCommands: repin.sh exited $status, want 0: $(cat "$tmp/out")"
}

# A carried commit of our own that changes the same line as the new release
# still stops the re-pin with a conflict that names it.
test_reports_a_conflicting_carried_commit() {
  local tmp
  tmp=$(mktemp -d)
  trap 'cd /; rm -rf "$tmp"' RETURN

  # Arrange
  git init -q -b master "$tmp/upstream"
  (
    cd "$tmp/upstream"
    commit_file go.mod 'tools v0.49' 'initial'
    git tag v1.0.0
    commit_file go.mod 'tools v0.52' 'bump tools to v0.52'
    git tag v1.0.1
  )
  git clone -q "$tmp/upstream" "$tmp/seed"
  (
    cd "$tmp/seed"
    git switch -q -c giantswarm v1.0.0
    commit_file go.mod 'tools v0.49-ours' 'feat: our change to go.mod'
  )
  git clone -q --bare "$tmp/seed" "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/work"
  cd "$tmp/work"
  git remote add upstream "$tmp/upstream"

  # Act
  local status=0
  UPSTREAM_REF=v1.0.1 CANDIDATE=sync/test REPORT="$tmp/report.md" REPORT_ENV="$tmp/report.env" \
    "$here/repin.sh" > "$tmp/out" 2>&1 || status=$?

  # Assert
  [ "$status" -eq 2 ] || fail "repin.sh exited $status, want 2: $(cat "$tmp/out")"
  grep -qx 'status=conflict' "$tmp/report.env" || fail "want status=conflict in report.env: $(cat "$tmp/report.env")"
  grep -qx 'conflict_subject=feat: our change to go.mod' "$tmp/report.env" || fail "want the conflict to name our commit: $(cat "$tmp/report.env")"
}

test_drops_carried_commits_that_the_release_contains
test_reports_a_conflicting_carried_commit
test_keeps_an_empty_carried_commit
test_drops_released_commits_with_abbreviated_commands

[ "$failed" -eq 0 ] && echo "ok repin_test.sh"
exit "$failed"
