#!/bin/sh
# Follows a project's install guide against the live repository in a fresh Debian or Ubuntu
# container. Given a package, also checks that the version just published is offered,
# installs it by name and runs the project's check command.
#
# Usage: check-install.sh <base-url> [<package> <version> <upstream-version> <command>...]
set -eu

base=$1
shift
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq ca-certificates curl >/dev/null
curl -fsSL "$base/shortarrow-archive-keyring.gpg" -o /usr/share/keyrings/shortarrow-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/shortarrow-archive-keyring.gpg] $base stable main" \
  >/etc/apt/sources.list.d/shortarrow.list
apt-get update -qq
apt-get install -y -qq shortarrow-archive-keyring >/dev/null
echo "OK: apt update and the keyring package from $base"

[ $# -eq 0 ] && exit 0
package=$1
version=$2
upstream=$3
shift 3

apt-cache madison "$package" | tee /dev/stderr |
  awk -F'|' -v want="$version" '{ gsub(/ /, "", $2) } $2 == want { found = 1 } END { exit !found }'
apt-get install -y -qq "$package=$version" >/dev/null
output=$("$@")
echo "$output"
case $output in
*"$upstream"*) echo "OK: $package $version installs and '$*' prints $upstream" ;;
*)
  echo "FAIL: '$*' does not print $upstream" >&2
  exit 1
  ;;
esac
