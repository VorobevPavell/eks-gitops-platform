#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 <env> <tag> <reason>" >&2; exit 2; }
(( $# == 3 )) || usage
env=$1 tag=$2 reason=$3

cd "$(git rev-parse --show-toplevel)"
values="gitops/envs/$env/values.yaml"
[[ -f "$values" ]] || { echo "no such environment: $env" >&2; exit 1; }
[[ "$tag" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || { echo "invalid image tag: $tag" >&2; exit 1; }

current=$(yq '.image.tag' "$values")
if [[ "$current" == "$tag" ]]; then
  echo "$env already runs $tag"
  exit 0
fi

TAG=$tag yq -i '.image.tag = strenv(TAG)' "$values"
git add "$values"
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit --quiet -m "deploy(hello): ${current} -> ${tag} to ${env}" -m "${reason}"

for attempt in 1 2 3; do
  if git push --quiet origin HEAD; then
    echo "$env: $current -> $tag"
    exit 0
  fi
  echo "push rejected (attempt $attempt), rebasing onto origin" >&2
  git pull --rebase --quiet origin "$(git rev-parse --abbrev-ref HEAD)"
done
echo "could not push after 3 attempts" >&2
exit 1
