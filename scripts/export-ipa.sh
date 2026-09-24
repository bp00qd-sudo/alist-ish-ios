#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/ios/AlistApp/AlistApp.xcodeproj"
archive_path="${ARCHIVE_PATH:-$repo_root/build/Alist.xcarchive}"
export_path="${EXPORT_PATH:-$repo_root/build/ipa}"
configuration="${CONFIGURATION:-Release}"
export_options="${EXPORT_OPTIONS_PLIST:-}"

if [[ ! -d "$project" ]]; then
  echo "Xcode project not found: $project" >&2
  exit 2
fi
if [[ -z "$export_options" || ! -f "$export_options" ]]; then
  cat >&2 <<'EOF'
Provide EXPORT_OPTIONS_PLIST pointing to an ExportOptions.plist created for
your Apple team/profile. The repository cannot contain a signing identity or
provisioning profile.
EOF
  exit 2
fi

mkdir -p "$(dirname "$archive_path")" "$export_path"
archive_args=(
  -project "$project"
  -target Alist
  -sdk iphoneos
  -configuration "$configuration"
  -archivePath "$archive_path"
  archive
)
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  archive_args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  archive_args+=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY")
fi
if [[ -n "${PROVISIONING_PROFILE_SPECIFIER:-}" ]]; then
  archive_args+=(PROVISIONING_PROFILE_SPECIFIER="$PROVISIONING_PROFILE_SPECIFIER")
fi

xcodebuild "${archive_args[@]}"
xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$export_path"

echo "IPA exported to $export_path"
