#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 <from-env> <to-env> <revision> <reason>" >&2; exit 2; }
(( $# == 4 )) || usage
from=$1 to=$2 reason=$4

die() { echo "$*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
git fetch --quiet origin main
revision=$(git rev-parse --verify --quiet "$3^{commit}") || die "unknown revision: $3"
git merge-base --is-ancestor "$revision" origin/main || die "$revision is not on main"

matches_revision() {
  git diff --quiet "$revision" "$1" -- charts || return 1
  [[ "$(git show "$revision:gitops/envs/$to/values.yaml" | yq 'del(.image.tag)')" == \
     "$(git show "$1:gitops/envs/$to/values.yaml" | yq 'del(.image.tag)')" ]]
}

matches_revision origin/main \
  || die "main changed charts/ or gitops/envs/$to after ${revision:0:7}: wait until $from runs the newer commit and promote that"

tag=$(git show "$revision:gitops/envs/$from/values.yaml" | yq '.image.tag')
scripts/set-image-tag.sh "$to" "$tag" "$reason"

matches_revision HEAD || die "main changed during the promotion; $to was not moved, run it again"
git push --quiet origin "HEAD:refs/heads/$to"
echo "$to now runs ${revision:0:7} with $tag"
