# The Giant Swarm Dex line

This repository is the Dex that Giant Swarm runs through [dex-app](https://github.com/giantswarm/dex-app): an upstream [dexidp/dex](https://github.com/dexidp/dex) release, plus the patches listed below. Every patch that upstream merges and releases is dropped here on the next re-pin.

| | |
|---|---|
| Consumed branch | `giantswarm`, the upstream release at the pin plus one commit per patch, and the default branch. Our release tags are cut from it. Every push to it needs a passing `ci-ok`, and only the sync's HeraldBot App may push to it without a pull request (the rulesets `devctl: line gate` and `devctl: default branch`, declared in `repositories/team-shield.yaml` of giantswarm/github). |
| Old fork | `main`, the old fork. Its CircleCI still builds the image the stable dex-app release uses, until dex-app ships the image from `giantswarm` as a stable release. |
| Mirror | `master`, the `v*` branches and upstream's tags, read-only copies of upstream. Never commit to them. |
| Upstream pin | the nearest upstream release tag in the history of `giantswarm`. `git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' origin/giantswarm` shows it, and the newest row of `re-pins.md` on the `ledger` branch names it too. |
| Tracking | giantswarm/giantswarm#34224 (the fork), giantswarm/giantswarm#38017 (sending the token exchange fixes upstream) |

## Carried commits

| Carried commit (subject) | Why we need it | Upstream |
|---|---|---|
| `fix(oidc): bound the fetch of the issuer's signing keys` | an issuer whose keys endpoint never answers makes every login and token exchange hang until Dex restarts | dexidp/dex#5050, open |
| `fix(oidc): answer token exchange with 503 when the issuer's keys can't be fetched` | callers of token exchange (muster) can tell an outage from a bad token | dexidp/dex#5055, open |
| `feat(server): put the connector ID in front of groups in issued tokens` | our identity providers and a customer's share one Dex, and `oidcGroupsPrefix: true` keeps their group names apart (`giantswarm-ad:<group>`, `customer:<group>`). dex-app turns it on. Our RBAC bindings and Kyverno policies use the prefixed names | fork-only. Upstream's `modifyGroupNames` prefix exists only for the `oidc` connector type, and our `microsoft` and `github` connectors can't use it |
| `ci: update linter version` | upstream's `ci.yaml` installs the newest Go 1.27, and golangci-lint 2.13.1 can't read what Go 1.27.3 compiles, so its Lint job fails on our pull requests | upstream commit `0f16f5f4` on `master`, not released yet |
| `build(deps): bump golang.org/x/tools to v0.50.0` | the next commit applies only on top of this one | upstream commit `6a4849d2` on `master`, not released yet |
| `build(deps): bump golang.org/x/tools to v0.52.0` | with `x/tools` v0.49.0, `make generate-ent` can't read what Go 1.27.3 compiles, so the Test job of upstream's `ci.yaml` fails on our pull requests | upstream commit `12190976` on `master`, not released yet |
## What is published

CircleCI (`.circleci/config.yml`) builds the image `gsoci.azurecr.io/giantswarm/dex/dex` for amd64 and arm64:

- On every push to `giantswarm` it publishes a dev build, tagged with a dev version like `2.46.2-r91661b28t20261105152745h24f495b`. It names the next patch version, then the commit.
- On every release tag `vX.Y.Z-gs.N` it publishes that version, like `2.46.1-gs.1`.
- On every other branch, like pull requests and `sync/**` branches, it builds both images and publishes nothing.

Note that the image name is `giantswarm/dex/dex`, not `giantswarm/dex`. retagger copies upstream's images to `giantswarm/dex`, so that name holds upstream Dex without our patches.

## Release scheme

Our versions are the upstream release we're on, plus `-gs.N`. `v2.46.1-gs.1` is our first release on top of upstream `v2.46.1`, `v2.46.1-gs.2` the next one, and `v2.47.0-gs.1` the first one after the re-pin onto upstream `v2.47.0`. Upstream never uses `-gs.N`, so the tags the mirror copies from upstream never clash with ours.

Releases are cut automatically. On every push to `giantswarm`, `.github/workflows/fork-release.yaml` tags the next release with `scripts/fork/next-release.sh`:

- After a re-pin onto a new upstream release, the push gets `-gs.1` of that release.
- After a merged pull request, the push gets the next number, like `-gs.2`.
- A push that only changes Markdown files, `.github` or `scripts/fork` gets no release, because none of them go into the image.

If you ever need a release by hand, tag the head of `giantswarm` with the next free number and push the tag:

```bash
git tag v2.46.1-gs.2 origin/giantswarm
git push origin v2.46.1-gs.2
```

Note that gitsemver only takes `vX.Y.Z-gs.N` as a release version when `GS_GIT_TAG_SUFFIX` is `gs`. This is set as an environment variable in the CircleCI project settings of giantswarm/dex, not in the repository. Without it the tag pipeline builds a dev version.

Note also that `-gs.N` is a semver pre-release, so `2.46.1-gs.1` sorts below `2.46.1`. That's fine here, because upstream's `2.46.1` never exists in `giantswarm/dex/dex`.

## Re-pin

A re-pin moves `giantswarm` onto a newer upstream release and replays our commits on top. The workflow `.github/workflows/sync-upstream.yaml` does it every Monday at 05:00 UTC, onto the newest upstream release. If there's no new release, the run does nothing. You can also start it by hand, with the inputs `upstream_ref` (a release tag like `v2.47.0`, or `latest`), `dry_run` and `mirror_only`. A run you start is a dry run unless you set `dry_run` to false. The Monday run is a real one.

Note that GitHub starts scheduled and dispatched runs only from the default branch, which is `giantswarm`.

One run does this:

1. It copies upstream's `master`, its `v*` branches and its tags into this repository (`scripts/fork/mirror.sh`). Then it cancels the upstream workflows that this push starts (`scripts/fork/mirror-quiet.sh`). See "The mirror".
2. It replays our commits onto the upstream release in a new branch `sync/upstream-<date>-<release>` (`scripts/fork/repin.sh`). Our commits are the ones between the pinned release and the head of `giantswarm`. A commit that upstream has released in the meantime drops out, and the report names the upstream commit it landed as. Then `scripts/fork/hunks.py` checks that every line our commits change is still there. If a change is missing, the run stops and names the commit, the file and the place.
3. It pushes the new branch as the org's heraldbot GitHub App. `fork-ci.yaml` runs `make test`, `make lint` and the tests of the fork scripts (`scripts/fork/repin_test.sh`) on it, and the sync waits for its `ci-ok` check.
4. If `ci-ok` passes, it force-pushes the new branch onto `giantswarm`, deletes the new branch, and adds a row to `re-pins.md` on the `ledger` branch.
5. If one of our commits conflicts with upstream, or `ci-ok` fails, nothing is pushed to `giantswarm`. Instead the run opens a pull request against `giantswarm` that names the commit and the files, or the failed check. Finish the re-pin by hand (see "Manual re-pin"), then close that pull request. Don't merge it.

A re-pin only moves forward. The scripts refuse a release that's older than the pin.

After a re-pin that dropped a commit, remove its row from the table above in a pull request.

### Manual re-pin

If the workflow stops on a conflict, do the same steps by hand:

```bash
git clone https://github.com/giantswarm/dex && cd dex
git switch giantswarm
git remote add upstream https://github.com/dexidp/dex.git
RELEASE=v2.47.0
PIN=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' origin/giantswarm)
UPSTREAM_REF=$RELEASE CANDIDATE=sync/upstream-$(date -u +%Y%m%d)-$RELEASE-manual scripts/fork/repin.sh
```

Set `RELEASE` to the release you re-pin onto. `repin.sh` exits with 2 on a conflict and writes `repin-report.md`. Then:

1. Rebase by hand and fix the conflict in the commit the report names: `git rebase --onto "$RELEASE" "$PIN"`.
2. Check that no change got lost: `scripts/fork/hunks.py "$PIN" origin/giantswarm HEAD`.
3. Run `make test` and `make lint`.
4. Push the result to a `sync/**` branch. `fork-ci.yaml` runs on it.
5. Start the workflow with that branch as `candidate` and the release it sits on as `upstream_ref`. The workflow checks the branch with `scripts/fork/take-candidate.sh`, waits for `ci-ok` and lands it the same way as its own re-pins. Nobody force-pushes `giantswarm` by hand.

If the re-pin drops or reworks one of our changes on purpose, name it in the input `accept_hunks`, as `hunks.py` prints it.

### The mirror

`master`, the `v*` branches and the tags are read-only copies of upstream. Never commit to them. `mirror.sh` only moves them forward and never deletes one. If a copied branch was changed, the run stops. Restore the branch with `git push --force-with-lease=refs/heads/<branch> origin upstream/<branch>:<branch>`, then start the workflow again.

The old fork's own tags (`v2.43.2`, `v2.43.3`) look like upstream versions that upstream never released. If upstream ever releases a tag with the same name, `mirror.sh` stops and names it, instead of overwriting either one.

The mirror is pushed with the heraldbot App's token, because GitHub refuses a push with the workflow's own token when it adds or changes a file under `.github/workflows`, and upstream's commits do that.

## Ledger

The `ledger` branch has no shared history with the code. The sync adds one row to `re-pins.md` there for each re-pin it lands. A re-pin that stopped is a pull request, not a row.
