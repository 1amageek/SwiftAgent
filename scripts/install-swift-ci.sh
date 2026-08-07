#!/usr/bin/env bash
set -euo pipefail

snapshot="swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a"
expected_commit="ef761e567dc94ee"
toolchain_identifier="org.swift.64202607231a"
download_root="https://download.swift.org/swift-6.4.x-branch"
temporary_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
temporary_directory="$(mktemp -d "$temporary_parent/swift-toolchain.XXXXXX")"

cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

toolchain_root="$HOME/Library/Developer/Toolchains/$snapshot.xctoolchain"
if [[ ! -x "$toolchain_root/usr/bin/swift" ]]; then
  package_path="$temporary_directory/$snapshot-osx.pkg"
  package_url="$download_root/xcode/$snapshot/$snapshot-osx.pkg"
  curl --fail --location --show-error "$package_url" --output "$package_path"

  signature="$(pkgutil --check-signature "$package_path")"
  if [[ "$signature" != *"Developer ID Installer: Swift Open Source (V9AUD2URP3)"* ]]; then
    echo "Swift toolchain package signature verification failed." >&2
    echo "$signature" >&2
    exit 1
  fi

  installer -pkg "$package_path" -target CurrentUserHomeDirectory
fi

toolchain_linker="$toolchain_root/usr/bin/ld"
if [[ ! -x "$toolchain_linker" ]]; then
  xcode_linker="$(xcrun --toolchain XcodeDefault --find ld)"
  if [[ ! -x "$xcode_linker" ]]; then
    echo "The active Xcode toolchain does not provide an executable linker: $xcode_linker" >&2
    exit 1
  fi
  if [[ -L "$toolchain_linker" ]]; then
    unlink "$toolchain_linker"
  elif [[ -e "$toolchain_linker" ]]; then
    echo "The Swift toolchain linker path exists but is not executable: $toolchain_linker" >&2
    exit 1
  fi
  ln -s "$xcode_linker" "$toolchain_linker"
fi

swift_binary="$(xcrun --toolchain "$toolchain_identifier" --find swift)"
version="$($swift_binary --version)"
if [[ "$version" != *"Swift $expected_commit"* ]]; then
  echo "Unexpected Swift compiler. Required commit: $expected_commit" >&2
  echo "$version" >&2
  exit 1
fi

echo "$version"
printf '%s\n' "${swift_binary%/swift}" >> "$GITHUB_PATH"
printf 'TOOLCHAINS=%s\n' "$toolchain_identifier" >> "$GITHUB_ENV"
