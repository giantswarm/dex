# The Giant Swarm Dex line

This repository is the Dex that Giant Swarm runs through [dex-app](https://github.com/giantswarm/dex-app): upstream [dexidp/dex](https://github.com/dexidp/dex) `master` at a pinned commit, plus the patches listed below. Every patch that upstream merges and releases is dropped here on the next re-pin.

| | |
|---|---|
| Consumed branch | `giantswarm`, upstream at the pin plus one commit per patch. Release tags are cut from it. It becomes the default branch when the old `main` is retired. Until then dex-app still uses the image built from `main`. |
| Mirror | `master` and upstream's tags, read-only copies of upstream. Never commit to them. |
| Upstream pin | `b02ead0b` (upstream `master`, 2026-10-26). `git merge-base giantswarm master` shows it. |
| Tracking | giantswarm/giantswarm#34224 (the fork), giantswarm/giantswarm#38017 (sending the token exchange fixes upstream) |

## What is published

`.circleci/config.yml` builds upstream's `Dockerfile` as it is, with the architect orb's stock jobs. It builds one image per architecture (amd64 and arm64, each on a machine of that architecture), then joins them into one tagged index, signs it with cosign keyless and attests it.

| | |
|---|---|
| Image | `gsoci.azurecr.io/giantswarm/dex/dex:<version>`, multi-arch. The index carries the annotation `io.giantswarm.upstream.version=master@<pin sha7>`. Note that `gsoci.azurecr.io/giantswarm/dex` is something else: retagger's copy of upstream's images, and the old fork's builds from `main`. |
| Dev version, on every push to `giantswarm` | gitsemver's dev shape, `X.Y.Z-r<branch hash>t<YYYYMMDDHHMMSS>h<sha7>`. `X.Y.Z` is the next patch above the newest stable tag reachable from the commit. That's upstream's mirrored tag until the line's first release is on the branch. |
| Release version, on a tag `v3.Y.Z` or `v3.Y.Z-rc.N` | the tag without `v` |

Every other branch of the line, like a pull request or a `sync/**` candidate, runs the same two builds and pushes nothing. The mirrored upstream refs (`master`, `v2.*.x`, upstream's tags) build nothing.

### Release scheme

A release is a tag `vX.Y.Z` on `giantswarm`. The version is the line's own semver and says nothing about upstream's version. The pin above and the image's annotation record which upstream it's built from. A release candidate is `vX.Y.Z-rc.N`.

The line's versions start at `3.0.0`, one major above upstream's. Upstream's tags are `v2.*`, and the mirror copies them into this repository, so the two must never use the same name. If upstream ever starts a `v3`, the line moves to its next major first.

Cut a tag only after the dev build of the same commit has been tested with dex-app:

```bash
git tag -a v3.0.0 -m v3.0.0 <sha> && git push origin v3.0.0
```

## Carried commits

| Carried commit (subject) | Why we need it | Upstream |
|---|---|---|
| `fix(oidc): bound the fetch of the issuer's signing keys` | an issuer whose keys endpoint never answers makes every login and token exchange hang until Dex restarts | dexidp/dex#5050, open |
| `fix(oidc): answer token exchange with 503 when the issuer's keys can't be fetched` | callers of token exchange (muster) can tell an outage from a bad token | dexidp/dex#5055, open |
| `feat(server): put the connector ID in front of groups in issued tokens` | our identity providers and a customer's share one Dex, and `oidcGroupsPrefix: true` keeps their group names apart (`giantswarm-ad:<group>`, `customer:<group>`). dex-app turns it on. Our RBAC bindings and Kyverno policies use the prefixed names | fork-only. Upstream's `modifyGroupNames` prefix exists only for the `oidc` connector type, and our `microsoft` and `github` connectors can't use it |

## Re-pin

A re-pin moves `giantswarm` onto a newer upstream `master` and replays our commits on top. The workflow `.github/workflows/sync-upstream.yaml` does it every Monday at 05:00 UTC. You can also start it by hand, with the inputs `upstream_ref`, `dry_run` and `mirror_only`. A run you start is a dry run unless you set `dry_run` to false. The Monday run is a real one.

Note that GitHub starts scheduled and dispatched runs only from the default branch. Until `giantswarm` is the default branch, a short workflow on `main` calls this one.

One run does this:

1. It copies upstream's `master`, its `v*` branches and its tags into this repository (`scripts/fork/mirror.sh`). Then it cancels the upstream workflows that this push starts (`scripts/fork/mirror-quiet.sh`). See "The mirror".
2. It replays our commits onto upstream `master` in a new branch `sync/upstream-<date>-<sha7>` (`scripts/fork/repin.sh`). A commit that upstream has merged in the meantime drops out, and the report names the upstream commit it landed as. Then `scripts/fork/hunks.py` checks that every line our commits change is still there. If a change is missing, the run stops and names the commit, the file and the place.
3. It pushes the new branch as the org's heraldbot GitHub App. `fork-ci.yaml` runs `make test` and `make lint` on it, and the sync waits for its `ci-ok` check.
4. If `ci-ok` passes, it force-pushes the new branch onto `giantswarm`, deletes the new branch, and adds a row to `re-pins.md` on the `ledger` branch.
5. If one of our commits conflicts with upstream, or `ci-ok` fails, nothing is pushed to `giantswarm`. Instead the run opens a pull request against `giantswarm` that names the commit and the files, or the failed check. Finish the re-pin by hand (see "Manual re-pin"), then close that pull request. Don't merge it.

After a re-pin that dropped a commit, remove its row from the table above in a pull request, and update the pin.

After every re-pin, move the pin annotation in `.circleci/config.yml` to the new pin in a pull request against `giantswarm`. The sync doesn't edit it:

```bash
sed -i "s|upstream.version=master@[0-9a-f]*|upstream.version=master@$(git merge-base HEAD master | cut -c1-7)|" .circleci/config.yml
```

### Manual re-pin

If the workflow stops on a conflict, do the same steps by hand:

```bash
git clone https://github.com/giantswarm/dex && cd dex
git switch giantswarm
git remote add upstream https://github.com/dexidp/dex.git
CANDIDATE=sync/upstream-$(date -u +%Y%m%d)-manual scripts/fork/repin.sh
```

`repin.sh` exits with 2 on a conflict and writes `repin-report.md`. Then:

1. Rebase by hand and fix the conflict in the commit the report names: `git rebase --onto upstream/master "$(git merge-base origin/giantswarm upstream/master)"`.
2. Check that no change got lost: `scripts/fork/hunks.py "$(git merge-base origin/giantswarm upstream/master)" origin/giantswarm HEAD`.
3. Run `make test` and `make lint`.
4. Push the result to a `sync/**` branch. `fork-ci.yaml` runs on it.
5. Start the workflow with that branch as `candidate` and the upstream commit it sits on as `upstream_ref`. The workflow checks the branch with `scripts/fork/take-candidate.sh`, waits for `ci-ok` and lands it the same way as its own re-pins. Nobody force-pushes `giantswarm` by hand.

If the re-pin drops or reworks one of our changes on purpose, name it in the input `accept_hunks`, as `hunks.py` prints it.

### The mirror

`master`, the `v*` branches and the tags are read-only copies of upstream. Never commit to them. `mirror.sh` only moves them forward and never deletes one. If a copied branch was changed, the run stops. Restore the branch with `git push --force-with-lease=refs/heads/<branch> origin upstream/<branch>:<branch>`, then start the workflow again.

The old fork's own tags (`v2.43.2`, `v2.43.3`) look like upstream versions that upstream never released. If upstream ever releases a tag with the same name, `mirror.sh` stops and names it, instead of overwriting either one.

The mirror is pushed with the heraldbot App's token, because GitHub refuses a push with the workflow's own token when it adds or changes a file under `.github/workflows`, and upstream's commits do that.

## Ledger

The `ledger` branch has no shared history with the code. The sync adds one row to `re-pins.md` there for each re-pin it lands. A re-pin that stopped is a pull request, not a row.
