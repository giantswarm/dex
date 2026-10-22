#!/usr/bin/env bash
# Push as a given token: `scripts/fork/git-push-as.sh <token> <git push args…>`.
# The workflows use it to choose who pushes. The workflow's own GITHUB_TOKEN
# makes a push that starts no workflow and may not touch workflow files, which
# is right for the ledger. The App's token makes a push that does start
# workflows and may update .github/workflows, which the consumed branch, the
# sync candidates and the mirror need.
set -euo pipefail
token=$1
shift
auth=$(printf 'x-access-token:%s' "$token" | base64 -w0)
# Mask the encoded credential in the Actions log. Outside Actions the line would
# print it, so it is only emitted where the runner interprets it.
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::${auth}"
exec git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${auth}" push "$@"
