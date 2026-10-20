# CLAUDE.md

This repository is Giant Swarm's fork of [dexidp/dex](https://github.com/dexidp/dex). We keep it as close to upstream as we can, so that one day we can use upstream Dex directly. The section "What this fork changes" in `README.md` lists every change the fork makes to Dex code.

## Changing Dex code

- Add or update the change's row in the README table, in the same pull request as the code.
- Open an upstream pull request for the change, unless it only makes sense for Giant Swarm, and link it in the table.
- Add an entry to `CHANGELOG.md`.

## Moving to a newer upstream release

First, fetch upstream's tags into their own namespace. The fork has its own tags like `v2.43.3` that look like upstream versions but aren't, so the two sets must not mix:

```sh
git remote add --no-tags upstream https://github.com/dexidp/dex.git  # only once
git fetch --no-tags upstream '+refs/tags/*:refs/upstream-tags/*'
```

Then compare the fork with upstream by content. The git history doesn't show what the fork changes, because the fork's merge base with upstream is a commit from 2023:

```sh
git diff --stat refs/upstream-tags/$(cat .upstream-version) origin/main
```

Then go through the README table. If the new upstream release has a change, drop the fork's version and delete its row.

Finally, update `.upstream-version`. Check that every file in the diff is in the README table, is a test for one of its rows, or is a CI or repository file.
