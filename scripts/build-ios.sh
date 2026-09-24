#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
go_root="$repo_root/alist"
out_dir="$repo_root/build"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-ios.sh must run on macOS (Xcode is required)." >&2
  exit 2
fi
command -v xcodebuild >/dev/null || { echo "Xcode is required" >&2; exit 2; }
command -v go >/dev/null || { echo "Go is required" >&2; exit 2; }
command -v gomobile >/dev/null || { echo "Install gomobile first: go install golang.org/x/mobile/cmd/gomobile@latest" >&2; exit 2; }

if [[ ! -f "$go_root/public/dist/index.html" ]]; then
  echo "Alist web assets are missing; run scripts/fetch-web-dist.sh first." >&2
  exit 2
fi

mkdir -p "$out_dir"
pushd "$go_root" >/dev/null
download_ok=false
for attempt in 1 2 3; do
  if go mod download; then
    download_ok=true
    break
  fi
  echo "go module download failed (attempt ${attempt}/3); retrying..." >&2
  sleep 5
done
if [[ "$download_ok" != true ]]; then
  echo "unable to download Go dependencies after 3 attempts" >&2
  exit 1
fi

# gopsutil's Darwin cgo files target macOS-only headers (libproc, SMC and
# mach APIs). The package already ships portable no-cgo implementations. Copy
# the module into a build-local directory and use a temporary replace so the
# read-only module cache is never modified and gomobile's generated module
# sees the same compatibility source.
gopsutil_dir="$(go list -m -f '{{.Dir}}' github.com/shirou/gopsutil/v3)"
gopsutil_copy="$(mktemp -d "$out_dir/gopsutil-ios.XXXXXX")"
cp -R "$gopsutil_dir/." "$gopsutil_copy/"
chmod -R u+w "$gopsutil_copy"
compat_files=(
  cpu/cpu_darwin_cgo.go cpu/cpu_darwin_nocgo.go
  process/process_darwin_cgo.go process/process_darwin_nocgo.go
  mem/mem_darwin_cgo.go mem/mem_darwin_nocgo.go
  host/host_darwin_cgo.go host/host_darwin_nocgo.go
)
# These C translation units are picked up by the Go package even when their
# companion cgo Go files are excluded. They target macOS-only SMC/iostat APIs;
# remove them from the disposable copy so iOS uses the no-cgo implementations.
rm -f "$gopsutil_copy/disk/iostat_darwin.c" "$gopsutil_copy/host/smc_darwin.c"
for rel in "${compat_files[@]}"; do
  file="$gopsutil_copy/$rel"
  chmod u+w "$file"
  if [[ "$rel" == *_cgo.go ]]; then
    rewritten="$(perl -0pe 's#//go:build darwin && cgo\n// \+build darwin,cgo#//go:build darwin && cgo && !ios\n// +build darwin,cgo,!ios#' "$file")"
  else
    rewritten="$(perl -0pe 's#//go:build darwin && !cgo\n// \+build darwin,!cgo#//go:build (darwin && !cgo) || ios\n// +build darwin,!cgo ios#' "$file")"
  fi
  # Avoid perl -i: some hosted macOS runners deny temporary-file creation in
  # both the module cache and the checkout. The source is small enough to
  # rewrite through stdout and a direct redirection safely.
  printf '%s\n' "$rewritten" > "$file"
  if ! grep -q '^//go:build .*ios' "$file"; then
    echo "failed to prepare iOS gopsutil source: $rel" >&2
    exit 1
  fi
done
mod_backup="$out_dir/alist-go.mod.before-gopsutil-ios"
cp go.mod "$mod_backup"
restore_mod() { cp "$mod_backup" "$go_root/go.mod"; }
trap restore_mod EXIT
go mod edit -replace="github.com/shirou/gopsutil/v3=$gopsutil_copy"

# Surface module/package resolution in CI before gobind's own loader, whose
# diagnostics are intentionally terse.
go list -m -json golang.org/x/mobile > "$out_dir/x-mobile-module.json" || true
go list -json golang.org/x/mobile/bind > "$out_dir/x-mobile-bind.json" || true

# Keep a machine-readable compatibility report even when the package list has
# errors. This is useful for identifying desktop-only drivers on a new commit.
go list -e -tags=ios -f '{{if .Error}}{{.ImportPath}}: {{.Error.Err}}{{end}}' ./... \
  > "$out_dir/ios-driver-compatibility.txt" || true
go mod why -m github.com/shoenig/go-m1cpu \
  > "$out_dir/ios-m1cpu-why.txt" || true
cat "$out_dir/ios-m1cpu-why.txt"

gomobile bind \
  -target=ios/arm64 \
  -tags=ios \
  -trimpath \
  -ldflags='-s -w' \
  -o "$out_dir/AlistCore.xcframework" \
  ./iosbridge
popd >/dev/null

echo "Built $out_dir/AlistCore.xcframework"
