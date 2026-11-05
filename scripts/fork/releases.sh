# shellcheck shell=bash
# Upstream releases, sourced by repin.sh and take-candidate.sh (FORK.md,
# "Re-pin"). The consumed branch sits on an upstream release tag vX.Y.Z plus
# the carried commits. Our own release tags vX.Y.Z-gs.N and upstream's
# prereleases have a `-`, so they are never a pin.

is_release() { [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# The newest upstream release by version. Upstream cuts patch releases on v*.x
# branches, so the newest by date can be a patch of an older minor.
newest_release() {
  git tag -l 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1
}

# The release a commit of the consumed branch is pinned to: the nearest
# release tag in its history. merge-base with upstream can't tell, because a
# patch release is not on upstream's master.
pinned_release() {
  local tag
  tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' "$1")
  is_release "$tag" || { echo "the nearest tag below $1 is ${tag}, not an upstream release vX.Y.Z" >&2; return 1; }
  echo "$tag"
}

# older_release A B: A is an older release than B.
older_release() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$1" ]
}
