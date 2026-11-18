#!/usr/bin/env bash
# SwiftFormat check for the Swift files a branch changes, with a pinned
# SwiftFormat so CI and every laptop agree (brew floats; a newer release adds
# default rules and moves the goalposts).
#
#   scripts/swiftformat-changed.sh [BASE]          check (default BASE: origin/main)
#   scripts/swiftformat-changed.sh [BASE] --fix    format the files that fail the check
#
# Policy, because most of the repo predates formatting (51 of the 75 files
# touched in the last 15 commits fail):
#   - files the branch ADDS (or copies) must be formatted: the check fails;
#   - files it MODIFIES (or renames) are reported as warnings only, so an edit
#     to an old file never forces a whole-file reformat into someone's PR.
#
# Exit codes: 0 clean (or warnings only), 1 added files need formatting,
# 2 setup error (base not found, download failed, SwiftFormat crashed).
set -euo pipefail

VERSION="0.64.6"
# The compiler, not the language mode: trailing commas in argument lists (repo
# style) need 5.10+/6.1 semantics, and without a version SwiftFormat strips
# them. 6.2 is the oldest Xcode in use (26.2); CI runs 26.4.
SWIFT="6.2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/.swiftformat"
# Mirrors --exclude in .swiftformat; explicit file arguments bypass it.
EXCLUDE='^(\.build|\.swiftpm|DerivedData|LuminaVaultClient\.xcodeproj)/'

BASE="origin/main"
FIX=false
for arg in "$@"; do
  case "$arg" in
    --fix) FIX=true ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) BASE="$arg" ;;
  esac
done

FIX_CMD="scripts/swiftformat-changed.sh $BASE --fix"
in_ci() { [ -n "${GITHUB_ACTIONS:-}" ]; }

# --- pinned SwiftFormat -------------------------------------------------------
TOOLS="$ROOT/.build/tools/swiftformat-$VERSION-$(uname -s)-$(uname -m)"
case "$(uname -s)-$(uname -m)" in
  Darwin-*) ASSET="swiftformat.zip" ;;
  Linux-x86_64) ASSET="swiftformat_linux.zip" ;;
  Linux-aarch64 | Linux-arm64) ASSET="swiftformat_linux_aarch64.zip" ;;
  *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 2 ;;
esac
if [ ! -x "$TOOLS/swiftformat" ]; then
  mkdir -p "$TOOLS"
  url="https://github.com/nicklockwood/SwiftFormat/releases/download/$VERSION/$ASSET"
  echo "downloading SwiftFormat $VERSION ($ASSET)"
  curl -fsSL -o "$TOOLS/sf.zip" "$url" || { echo "download failed: $url" >&2; exit 2; }
  unzip -qo "$TOOLS/sf.zip" -d "$TOOLS/unpacked"
  bin="$(find "$TOOLS/unpacked" -type f -name 'swiftformat*' ! -name '*.zip' | head -1)"
  [ -n "$bin" ] || { echo "no swiftformat binary in $ASSET" >&2; exit 2; }
  mv "$bin" "$TOOLS/swiftformat"
  chmod +x "$TOOLS/swiftformat"
  rm -rf "$TOOLS/sf.zip" "$TOOLS/unpacked"
fi
SF="$TOOLS/swiftformat"
got="$("$SF" --version)"
[ "$got" = "$VERSION" ] || { echo "expected SwiftFormat $VERSION, got $got" >&2; exit 2; }

# --- changed files -------------------------------------------------------------
cd "$ROOT"
if ! MB="$(git merge-base "$BASE" HEAD 2>/dev/null)"; then
  echo "::error::cannot resolve merge-base of $BASE and HEAD — fetch the base branch (actions/checkout needs fetch-depth: 0)" >&2
  exit 2
fi

# NUL-separated so paths with spaces survive; deleted files are never listed.
ADDED=()
MODIFIED=()
while IFS= read -r -d '' f; do
  [[ "$f" =~ $EXCLUDE ]] || ADDED+=("$f")
done < <(git diff -z --name-only --diff-filter=AC "$MB" HEAD -- '*.swift')
while IFS= read -r -d '' f; do
  [[ "$f" =~ $EXCLUDE ]] || MODIFIED+=("$f")
done < <(git diff -z --name-only --diff-filter=MR "$MB" HEAD -- '*.swift')

echo "SwiftFormat $VERSION, base $BASE ($MB)"
echo "added Swift files (must be formatted): ${#ADDED[@]}"
for f in ${ADDED[@]+"${ADDED[@]}"}; do echo "  $f"; done
echo "modified Swift files (warnings only): ${#MODIFIED[@]}"
for f in ${MODIFIED[@]+"${MODIFIED[@]}"}; do echo "  $f"; done

# lint LEVEL FILES... prints findings (GitHub annotations in CI) and returns
# 0 clean, 1 needs formatting, 2 SwiftFormat error.
lint() {
  local level="$1"
  shift
  local out status=0 line file rest ln msg
  out="$("$SF" --lint --config "$CONFIG" --swift-version "$SWIFT" "$@" 2>&1)" || status=$?
  if [ "$status" -gt 1 ]; then
    printf '%s\n' "$out" >&2
    return 2
  fi
  while IFS= read -r line; do
    file="${line%%:*}"
    rest="${line#*:}"
    ln="${rest%%:*}"
    msg="${line#*: warning: }"
    msg="${msg#*: error: }"
    file="${file#"$ROOT"/}"
    if in_ci; then
      echo "::$level file=$file,line=$ln::SwiftFormat $VERSION: $msg"
    else
      echo "$level: $file:$ln: $msg"
    fi
  done < <(printf '%s\n' "$out" | grep -E ':[0-9]+:[0-9]+: (warning|error):' || true)
  return "$status"
}

failed=false
if [ "${#ADDED[@]}" -gt 0 ]; then
  status=0
  lint error "${ADDED[@]}" || status=$?
  [ "$status" -le 1 ] || exit 2
  [ "$status" -eq 0 ] || failed=true
fi
if [ "${#MODIFIED[@]}" -gt 0 ]; then
  status=0
  lint warning "${MODIFIED[@]}" || status=$?
  [ "$status" -le 1 ] || exit 2
  [ "$status" -eq 0 ] || echo "modified files have SwiftFormat findings (not blocking); format them only if the file is yours"
fi

if [ "$failed" = true ]; then
  if [ "$FIX" = true ]; then
    "$SF" --config "$CONFIG" --swift-version "$SWIFT" --quiet "${ADDED[@]}"
    echo "formatted the added files with SwiftFormat $VERSION; review and commit"
    exit 0
  fi
  msg="new Swift files are not formatted with SwiftFormat $VERSION. Fix locally: $FIX_CMD (it downloads $VERSION; brew's swiftformat may be a different version)"
  if in_ci; then echo "::error::$msg"; else echo "error: $msg"; fi
  exit 1
fi
echo "SwiftFormat check passed"
