#!/bin/bash
#
# ci-ocicl.sh -- install ocicl, then restore objc's dependencies into the objc
# checkout.  Used by .github/workflows/ci.yml; not needed on a developer's
# machine, where `cd objc && ocicl install' has already been done once.
#
#     tools/ci-ocicl.sh path/to/objc
#
# objc's ocicl.csv lists every Lisp dependency this project has -- cffi,
# alexandria, float-features, fiveam and the rest -- and this project has none
# of its own, so the restore runs inside the objc checkout.
#
# The retries are lifted from objc's own CI, where each was earned: the ocicl
# clone and setup have hung for a whole job budget on a runner, so each gets a
# watchdog and three attempts; and `ocicl install' exits 0 when a download from
# ghcr.io fails, which surfaced two steps later as "Component not found", so it
# is retried until no package is reported missing, and then fails loudly.

set -euo pipefail

objc="${1:?usage: $0 path/to/objc}"

# macOS ships no timeout(1).
attempt_with_timeout() {
  local secs=$1; shift
  ( "$@" ) & local pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) & local watchdog=$!
  local rc=0; wait "$pid" || rc=$?
  kill -9 "$watchdog" 2>/dev/null || true
  return $rc
}

clone_ocicl() {
  # The ocicl TOOL, cloned outside every checkout so it cannot collide with
  # the gitignored ocicl/ dependency directory in one.
  rm -rf "$HOME/ocicl-src"
  git clone --depth 1 https://github.com/ocicl/ocicl.git "$HOME/ocicl-src"
}

setup_ocicl() {
  ( cd "$HOME/ocicl-src" && sbcl --non-interactive --load setup.lisp )
}

for attempt in 1 2 3; do
  if attempt_with_timeout 300 clone_ocicl && attempt_with_timeout 300 setup_ocicl; then
    break
  fi
  if [ "$attempt" = 3 ]; then
    echo "::error::ocicl could not be installed after 3 attempts" >&2
    exit 1
  fi
  echo "::warning::ocicl install attempt $attempt failed or hung; retrying"
  sleep 15
done

export PATH="$HOME/.local/bin:$PATH"
ocicl setup

cd "$objc"
for attempt in 1 2 3 4 5; do
  ocicl install 2>&1 | tee ocicl-install.log
  if ! grep -q "failed to install" ocicl-install.log; then
    break
  fi
  echo "::warning::ocicl install attempt $attempt did not get every package"
  sleep 30
done
if grep -q "failed to install" ocicl-install.log; then
  echo "::error::ocicl could not install every dependency after 5 attempts" >&2
  exit 1
fi
echo "restored:"; ls ocicl
