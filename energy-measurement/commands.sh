#!/usr/bin/env bash

set -euo pipefail
STAGE="${1:?stage required: build | test}"

# Every stage runs from the repository root, as the upstream job does: npm
# resolves package.json and the Karma spec globs from the working directory.
cd /workspace

case "$STAGE" in

  # js.yml:30,33
  build)
    npm ci
    npm run js
    ;;

  # js.yml:36
  test)
    npm run js-test
    ;;

  *)
    echo "unknown stage: $STAGE" >&2
    exit 2
    ;;

esac
