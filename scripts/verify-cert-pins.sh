#!/usr/bin/env bash
#
# Fails when the TLS chain served by the managed API host no longer contains any
# CA pinned in CertificatePinning.swift.
#
# This is the tripwire that was missing. A Let's Encrypt CA rotation
# (YE1/Root X2 -> YR2/Root YR) once shipped straight to production and cancelled
# every request from every installed build: chat never replied, the chat inbox
# read "No chats yet", and the Brain tab span forever, with no visible error.
# Nothing in CI noticed, because nothing checked.
#
# Run it in CI on a schedule, not only on push - the chain changes on the CA's
# timetable, not on ours. A failure means: rotate the pins, bump pinsValidUntil,
# update CertificatePinningTests fixtures, and ship a build.
#
# Usage: Scripts/verify-cert-pins.sh [host]

set -euo pipefail

HOST="${1:-api.luminavault.fyi}"
SOURCE="$(dirname "$0")/../LuminaVaultClient/API/Core/CertificatePinning.swift"

if [[ ! -f "$SOURCE" ]]; then
  echo "error: cannot find CertificatePinning.swift at $SOURCE" >&2
  exit 2
fi

# Every 64-char lowercase hex literal in the pin file: both the SPKI set and the
# legacy DER set. Matching either form is a pass, exactly like the app does.
PINS="$(grep -oE '"[0-9a-f]{64}"' "$SOURCE" | tr -d '"' | sort -u)"

if [[ -z "$PINS" ]]; then
  echo "error: no pins found in $SOURCE" >&2
  exit 2
fi

CHAIN="$(mktemp)"
trap 'rm -f "$CHAIN" "$CHAIN".*' EXIT

if ! openssl s_client -connect "$HOST:443" -servername "$HOST" -showcerts \
    </dev/null 2>/dev/null | awk '/BEGIN CERT/,/END CERT/' > "$CHAIN"; then
  echo "error: could not retrieve the certificate chain for $HOST" >&2
  exit 2
fi

if [[ ! -s "$CHAIN" ]]; then
  echo "error: empty certificate chain for $HOST" >&2
  exit 2
fi

# Split the PEM bundle into one file per certificate. (Written with awk rather
# than csplit: BSD csplit on macOS has no -z, so the runner and CI disagree.)
awk -v prefix="$CHAIN." '
  /BEGIN CERT/ { n++ }
  n { print > (prefix n ".pem") }
' "$CHAIN"

matched=""
echo "chain presented by $HOST:"
for cert in "$CHAIN".*.pem; do
  subject="$(openssl x509 -in "$cert" -noout -subject | sed 's/^subject=//')"
  der_sha="$(openssl x509 -in "$cert" -outform der | shasum -a 256 | cut -d' ' -f1)"
  spki_sha="$(openssl x509 -in "$cert" -noout -pubkey \
    | openssl pkey -pubin -outform der | shasum -a 256 | cut -d' ' -f1)"

  hit=""
  if grep -qx "$spki_sha" <<<"$PINS"; then hit=" <- PINNED (spki)"; matched="yes"; fi
  if grep -qx "$der_sha" <<<"$PINS"; then hit=" <- PINNED (der)"; matched="yes"; fi

  echo "  $subject$hit"
  echo "      der=$der_sha"
  echo "      spki=$spki_sha"
done

if [[ -z "$matched" ]]; then
  cat >&2 <<EOF

FAIL: no certificate in the chain served by $HOST matches any pin in
      CertificatePinning.swift. Every shipped build is being blocked by its own
      pinning delegate right now.

      Fix: add the intermediate/root SPKI hash printed above to
      pinnedSPKISHA256, push pinsValidUntil forward, refresh the fixtures in
      CertificatePinningTests, and ship a build.
EOF
  exit 1
fi

echo
echo "OK: the chain contains a pinned CA."
