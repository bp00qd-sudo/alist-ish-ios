#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/alist/public/dist"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$dist_dir"
curl --fail --location --retry 3 \
  https://github.com/alist-org/alist-web/releases/download/3.64.0/dist.tar.gz \
  --output "$tmp_dir/dist.tar.gz"
echo "b80550662de42a2f8a72d35bca8ed66ec9ad0c24a9a02ceec6a01bf5038cf6f4  $tmp_dir/dist.tar.gz" | shasum -a 256 -c -
tar -xzf "$tmp_dir/dist.tar.gz" -C "$tmp_dir"
rm -rf "$dist_dir"
mv "$tmp_dir/dist" "$dist_dir"
echo "Fetched Alist web distribution into $dist_dir"
