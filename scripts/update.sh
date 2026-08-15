#!/usr/bin/env bash
set -euo pipefail

# Update the deepseek-harness (dsh) package to the latest published npm
# version. Computes a fresh tarball hash, regenerates the vendored
# package-lock.json, and recomputes the npm dependency hash.
#
# Run inside `nix develop` so `npm` and `prefetch-npm-deps` are on PATH.
#
# Exits 0 when there is nothing to do, 1 on failure, so callers can decide
# whether to commit.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pkg="package.nix"
lock="package-lock.json"

current="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$pkg" | head -n1)"
if [[ -z "$current" ]]; then
  echo "error: could not parse version from $pkg" >&2
  exit 1
fi

latest="$(curl -fsSL https://registry.npmjs.org/@deepseek-ai/dsh/latest | jq -r .version)"
if [[ -z "$latest" || "$latest" == "null" ]]; then
  echo "error: could not determine latest version from npm" >&2
  exit 1
fi

if [[ "$latest" == "$current" ]]; then
  echo "up to date: $current"
  exit 0
fi

echo "updating: $current -> $latest"

url="https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${latest}.tgz"

src_hash="$(nix store prefetch-file --json "$url" | jq -r .hash)"
echo "srcHash = $src_hash"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$url" | tar -xz -C "$tmp"

npm --prefix "$tmp/package" install \
  --package-lock-only --ignore-scripts --no-audit --no-fund

cp "$tmp/package/package-lock.json" "$lock"
echo "regenerated $lock"

npm_hash="$(prefetch-npm-deps "$lock")"
echo "npmDepsHash = $npm_hash"

sed -i "s/^  version = \".*\";$/  version = \"$latest\";/" "$pkg"
sed -i "s/^  srcHash = \".*\";$/  srcHash = \"$src_hash\";/" "$pkg"
sed -i "s/^  npmDepsHash = \".*\";$/  npmDepsHash = \"$npm_hash\";/" "$pkg"

echo "verifying build"
nix build ".#deepseek-harness" --no-link

echo "updated to $latest"
