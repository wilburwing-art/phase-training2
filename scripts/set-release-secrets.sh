#!/usr/bin/env bash
# Sets the 4 GitHub Secrets the release workflow needs for manual code signing.
#
# What you do manually first (Apple-side, can't be scripted):
#   1. developer.apple.com → Certificates → revoke any extra/stale
#      "Apple Distribution" certs so the team is back under the cap.
#   2. Keychain Access → find the Distribution cert you kept → right-click
#      → Export → save as cert.p12 with a password you remember.
#   3. developer.apple.com → Profiles → + → App Store → app id
#      com.phasetraining.app → pick the cert from step 2 →
#      download as PhaseTraining_AppStore.mobileprovision.
#
# Then run this script with the two file paths and the .p12 password:
#
#   scripts/set-release-secrets.sh ~/Downloads/cert.p12 ~/Downloads/PhaseTraining_AppStore.mobileprovision 'your-p12-password'
#
# It base64-encodes both files, generates a random KEYCHAIN_PASSWORD, and
# writes all 4 secrets via `gh secret set`. Re-running overwrites — safe to
# repeat if you rotate the cert or profile.

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <cert.p12> <profile.mobileprovision> <p12-password>" >&2
  exit 2
fi

CERT_P12="$1"
PROFILE="$2"
P12_PW="$3"

for f in "$CERT_P12" "$PROFILE"; do
  if [ ! -f "$f" ]; then
    echo "missing file: $f" >&2
    exit 1
  fi
done

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not installed — brew install gh" >&2
  exit 1
fi

KEYCHAIN_PW=$(openssl rand -base64 24)

gh secret set BUILD_CERTIFICATE_BASE64       --body "$(base64 -i "$CERT_P12")"
gh secret set BUILD_PROVISION_PROFILE_BASE64 --body "$(base64 -i "$PROFILE")"
gh secret set P12_PASSWORD                   --body "$P12_PW"
gh secret set KEYCHAIN_PASSWORD              --body "$KEYCHAIN_PW"

echo
echo "set 4 secrets. verify:"
gh secret list | grep -E 'BUILD_CERTIFICATE_BASE64|BUILD_PROVISION_PROFILE_BASE64|P12_PASSWORD|KEYCHAIN_PASSWORD'
echo
echo "now re-run the release workflow:"
echo "  gh workflow run release.yml"
