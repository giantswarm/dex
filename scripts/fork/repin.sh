#!/usr/bin/env bash
# The git half of the re-pin (FORK.md, "Re-pin"): rebase the consumed branch's
# carried commits onto an upstream release into a candidate branch and report.
# Pushing, testing and landing the candidate belong to the sync workflow, or
# to the person running the same steps by hand.
#
#   CONSUMED=giantswarm UPSTREAM_REMOTE=upstream UPSTREAM_REF=latest \
#   CANDIDATE=sync/upstream-<date>-<tag> scripts/fork/repin.sh
#
# UPSTREAM_REF is an upstream release tag (vX.Y.Z), or `latest` for the newest.
#
# Exit 0: the candidate branch exists locally (status=rebased) or nothing is to
# do (status=up-to-date). Exit 2: a carried commit conflicts (status=conflict).
# The rebase is aborted and the working tree is back on the consumed head.
# Exit 3: the rebase lost a carried hunk that ACCEPT_HUNKS does not name
# (status=lost-hunks, each named in the report). The candidate is not pushed.
# The report is written to $REPORT (markdown) and $REPORT_ENV (key=value).
set -euo pipefail

CONSUMED=${CONSUMED:-giantswarm}
UPSTREAM_REMOTE=${UPSTREAM_REMOTE:-upstream}
UPSTREAM_REF=${UPSTREAM_REF:-latest}
REPORT=${REPORT:-repin-report.md}
REPORT_ENV=${REPORT_ENV:-repin-report.env}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/fork/releases.sh
. "${here}/releases.sh"

git fetch -q origin "$CONSUMED"
git fetch -q "$UPSTREAM_REMOTE" '+refs/tags/v*:refs/tags/v*'
head=$(git rev-parse "origin/$CONSUMED")
pin_tag=$(pinned_release "$head")
target_tag=$UPSTREAM_REF
[ "$target_tag" != latest ] || target_tag=$(newest_release)
is_release "$target_tag" || { echo "UPSTREAM_REF ${target_tag} is not an upstream release tag vX.Y.Z" >&2; exit 1; }
if older_release "$target_tag" "$pin_tag"; then
  echo "UPSTREAM_REF ${target_tag} is older than the pin ${pin_tag}: a re-pin only moves forward" >&2
  exit 1
fi
pin=$(git rev-parse "${pin_tag}^{commit}")
target=$(git rev-parse "${target_tag}^{commit}")
CANDIDATE=${CANDIDATE:-sync/upstream-$(date -u +%Y%m%d)-${target_tag}}

short() { git rev-parse --short=7 "$1"; }
subject() { git show -s --format=%s "$1"; }
cdate() { git show -s --format=%cI "$1"; }
item() { printf -- '- `%s` %s\n' "$(short "$1")" "$(subject "$1")"; }
patch_id() { git diff-tree -p "$1" | git patch-id --stable | awk '{print $1}'; }
env_out() { printf '%s=%s\n' "$1" "$2" >> "$REPORT_ENV"; }

mapfile -t carried < <(git rev-list --reverse --no-merges "$pin..$head")

: > "$REPORT_ENV"
env_out consumed "$CONSUMED"
env_out old_head "$head"
env_out pin "$pin"
env_out pin_tag "$pin_tag"
env_out target "$target"
env_out target_tag "$target_tag"
env_out candidate "$CANDIDATE"

{
  printf '### Re-pin `%s` onto upstream `%s`\n\n' "$CONSUMED" "$target_tag"
  printf '| | release | commit | date |\n|---|---|---|---|\n'
  printf '| previous pin | `%s` | `%s` | %s |\n' "$pin_tag" "$(short "$pin")" "$(cdate "$pin")"
  printf '| new pin | `%s` | `%s` | %s |\n' "$target_tag" "$(short "$target")" "$(cdate "$target")"
  printf '| consumed head before | | `%s` | %s |\n\n' "$(short "$head")" "$(cdate "$head")"
  printf '%d upstream commits since the previous pin.\n\n' "$(git rev-list --count "$pin..$target")"
  printf '#### Carried commits (%d, in order)\n\n' "${#carried[@]}"
  for c in "${carried[@]}"; do item "$c"; done
  printf '\n'
} > "$REPORT"

if [ "$pin" = "$target" ]; then
  printf 'Nothing to do: the consumed branch is already based on upstream `%s`.\n' "$target_tag" >> "$REPORT"
  env_out status up-to-date
  exit 0
fi

# Upstream commits in the new release and not in the pinned one, by patch id:
# names the upstream commit a dropped carried commit was merged as. Upstream
# cuts patch releases on a v*.x branch, so the pin need not be an ancestor of
# the target, and the carried commits are pin..head, not merge-base..head.
declare -A upstream_by_patch=()
while read -r sha; do
  upstream_by_patch[$(patch_id "$sha")]=$sha
done < <(git rev-list --no-merges "$pin..$target")

git checkout -q -B "$CANDIDATE" "$head"
# --autosquash folds an `amend!` or `fixup!` commit into the carried commit it
# names: the way a carried commit's diff or message is corrected between re-pins.
if ! git rebase --quiet --autosquash --no-reapply-cherry-picks --empty=drop --onto "$target" "$pin" 2> rebase.err; then
  conflict=$(git rev-parse REBASE_HEAD)
  applied=$(git rev-parse HEAD)
  mapfile -t files < <(git diff --name-only --diff-filter=U)
  git rebase --abort
  git checkout -q --detach "$head"
  {
    printf '#### Conflict\n\n'
    printf 'Carried commit `%s` %s does not apply onto upstream `%s`.\n\n' "$(short "$conflict")" "$(subject "$conflict")" "$target_tag"
    printf 'Conflicting files:\n\n'
    for f in "${files[@]}"; do printf -- '- `%s`\n' "$f"; done
    printf '\nCommits replayed before it: %d (`%s`).\n\n' "$(git rev-list --count "$target..$applied")" "$(short "$applied")"
    printf 'Resolve by hand (FORK.md, "Manual re-pin"): rebase the carried commits onto `%s`, fix the conflict in that commit, push the result to a `sync/**` branch, and start the sync workflow with it as `candidate`.\n' "$target_tag"
  } >> "$REPORT"
  env_out status conflict
  env_out conflict "$conflict"
  env_out conflict_subject "$(subject "$conflict")"
  exit 2
fi

new_head=$(git rev-parse HEAD)
mapfile -t replayed < <(git rev-list --reverse --no-merges "$target..$new_head")
dropped=()
{
  printf '#### Replayed (%d)\n\n' "${#replayed[@]}"
  for c in "${replayed[@]}"; do item "$c"; done
  printf '\n'
} >> "$REPORT"

# A carried commit with no replayed commit of the same subject was dropped:
# merged upstream (same patch id in the upstream range) or superseded.
declare -A replayed_subjects=()
for c in "${replayed[@]}"; do replayed_subjects[$(subject "$c")]=$c; done
for c in "${carried[@]}"; do
  s=$(subject "$c")
  [ -n "${replayed_subjects[$s]:-}" ] && continue
  dropped+=("$c")
done
if [ ${#dropped[@]} -gt 0 ]; then
  printf '#### Dropped (%d)\n\n' "${#dropped[@]}" >> "$REPORT"
  for c in "${dropped[@]}"; do
    up=${upstream_by_patch[$(patch_id "$c")]:-}
    if [[ $(subject "$c") =~ ^(amend|fixup|squash)!\  ]]; then
      printf -- '- `%s` %s: folded into its commit\n' "$(short "$c")" "$(subject "$c")"
    elif [ -n "$up" ]; then
      printf -- '- `%s` %s: merged upstream as `%s`\n' "$(short "$c")" "$(subject "$c")" "$(short "$up")"
    else
      printf -- '- `%s` %s: empty after the rebase (superseded upstream)\n' "$(short "$c")" "$(subject "$c")"
    fi
  done >> "$REPORT"
  printf '\nRemove the dropped commits'"'"' rows from the table in FORK.md in a follow-up pull request.\n\n' >> "$REPORT"
fi

# Every hunk the carried commits brought is in the candidate as it is in the
# consumed head, unless ACCEPT_HUNKS names it as dropped or reworked on purpose.
if ! scripts/fork/hunks.py "$pin" "$head" "$new_head" >> "$REPORT" 2>&1; then
  env_out status lost-hunks
  exit 3
fi

env_out status rebased
env_out new_head "$new_head"
env_out replayed_count "${#replayed[@]}"
env_out dropped_count "${#dropped[@]}"
env_out dropped "$(IFS=,; echo "${dropped[*]:-}")"
