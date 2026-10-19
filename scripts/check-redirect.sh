#!/bin/sh
# Usage: check-redirect.sh <base-url>
# Asserts that a pool path on <base-url> answers 302 to the matching GitHub release asset.
set -eu
base=${1:?usage: check-redirect.sh <base-url>}
path=apt/pool/ivi-cli/v0.4.0/SHA256SUMS
want=https://github.com/ShortArrow/ivi-cli/releases/download/v0.4.0/SHA256SUMS
headers=$(curl -sS -o /dev/null -D - "$base/$path" | tr -d '\r')
status=$(printf '%s\n' "$headers" | sed -n '1s/^HTTP[^ ]* \([0-9]*\).*/\1/p')
location=$(printf '%s\n' "$headers" | sed -n 's/^[Ll]ocation: //p')
if [ "$status" != 302 ] || [ "$location" != "$want" ]; then
  echo "FAIL: $base/$path -> $status $location (want 302 $want)" >&2
  exit 1
fi
echo "OK: $base/$path -> 302 $location"
