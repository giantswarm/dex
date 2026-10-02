# The Giant Swarm Dex line

This repository is the Dex that Giant Swarm runs through [dex-app](https://github.com/giantswarm/dex-app): upstream [dexidp/dex](https://github.com/dexidp/dex) `master` at a pinned commit, plus the patches listed below. Every patch that upstream merges and releases is dropped here on the next re-pin.

| | |
|---|---|
| Consumed branch | `giantswarm`, upstream at the pin plus one commit per patch. Release tags are cut from it. It becomes the default branch when the old `main` is retired. Until then dex-app still uses the image built from `main`. |
| Mirror | `master` and upstream's tags, read-only copies of upstream. Never commit to them. |
| Upstream pin | `416279bf` (upstream `master`, 2026-10-21). `git merge-base giantswarm master` shows it. |
| Tracking | giantswarm/giantswarm#34224 (the fork), giantswarm/giantswarm#38017 (sending the token exchange fixes upstream) |

## Carried commits

| Carried commit (subject) | Why we need it | Upstream |
|---|---|---|
| `fix(oidc): bound the fetch of the issuer's signing keys` | an issuer whose keys endpoint never answers makes every login and token exchange hang until Dex restarts | dexidp/dex#5050, open |
| `fix(oidc): answer token exchange with 503 when the issuer's keys can't be fetched` | callers of token exchange (muster) can tell an outage from a bad token | dexidp/dex#5055, open |
| `feat(server): put the connector ID in front of groups in issued tokens` | our identity providers and a customer's share one Dex, and `oidcGroupsPrefix: true` keeps their group names apart (`giantswarm-ad:<group>`, `customer:<group>`). dex-app turns it on. Our RBAC bindings and Kyverno policies use the prefixed names | fork-only. Upstream's `modifyGroupNames` prefix exists only for the `oidc` connector type, and our `microsoft` and `github` connectors can't use it |

## Re-pinning

1. Rebase `giantswarm` onto the newer upstream commit.
2. Drop every carried commit that upstream now contains, and remove its row above.
3. Run `make test` and `make lint`, update the pin in the table, and cut a release from `giantswarm`.
