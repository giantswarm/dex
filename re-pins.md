# Re-pins

Every re-pin of the `giantswarm` branch onto upstream, newest last (see FORK.md). Until 2026-11-05 the
pins are upstream `master` commits, since then upstream release tags. A re-pin
that stopped (conflict, failed checks) is a pull request against `giantswarm`, not a row.

| date (UTC) | previous pin | new pin | consumed head | replayed | dropped | run |
|---|---|---|---|---|---|---|
| 2026-10-27 08:53 | `416279b` | `b02ead0` (2026-10-26) | `38aa000` → `a2de959` | 5 | none | [run](https://github.com/giantswarm/dex/actions/runs/40476140610) |
| 2026-11-05 16:40 | `b02ead0` | `v2.46.1` (2026-10-21) | `47ca431` → `43f22f8` | 6 | none | by hand, giantswarm/dex#93 |
| 2026-11-05 17:17 | `v2.46.1` | `v2.46.0` (2026-10-08) | `43f22f8` → `782d8ab` | 4 | none, the fork's 3 own commits squashed into 1 | by hand, back to `v2.46.0` for a first release to test upgrades with |
| 2026-11-05 18:19 | `v2.46.0` | `v2.46.1` (2026-10-21) | `782d8ab` → `e05e7e8` | 4 | none | [run](https://github.com/giantswarm/dex/actions/runs/42082337723) |
