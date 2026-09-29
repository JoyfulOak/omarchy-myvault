#!/usr/bin/env bash
# Upload one encrypted MyVault payload as an asset on a GitHub Release.
set -euo pipefail
repo="${1:-}"
snapshot="${2:-}"
fail() { jq -n --arg error "$1" '{ok:false,error:$error}'; exit 1; }
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Repository must be owner/name.'
[[ -d "$snapshot" && ! -L "$snapshot" ]] || fail 'Snapshot folder is missing or unsafe.'
payload="$snapshot/payload.tar.gpg"
[[ -f "$payload" && ! -L "$payload" && -s "$payload" ]] || fail 'Encrypted payload.tar.gpg not found.'
command -v gh >/dev/null 2>&1 || fail 'GitHub CLI (gh) is required.'
gh auth status >/dev/null 2>&1 || fail 'Authenticate GitHub CLI first with: gh auth login'
private=$(gh repo view "$repo" --json isPrivate --jq '.isPrivate' 2>/dev/null) || fail 'Could not read GitHub repository; check owner/name and access.'
[[ "$private" == true ]] || fail 'Refusing to upload backups to a public repository.'
tag="myvault-$(date +%Y%m%d%H%M%S)-${RANDOM}"
gh release create "$tag" "$payload#payload.tar.gpg" --repo "$repo" --title "MyVault $tag" --notes 'Encrypted MyVault snapshot. Decryption requires the passphrase used during export.' >/dev/null 2>&1 || fail 'GitHub release upload failed.'
result=$(gh release view "$tag" --repo "$repo" --json url,assets 2>/dev/null) || fail 'Upload returned success, but release read-back verification failed.'
jq -e '.assets | any(.name == "payload.tar.gpg")' <<<"$result" >/dev/null || fail 'Release verification failed: encrypted backup asset is missing.'
jq -n --arg repo "$repo" --arg tag "$tag" --arg url "$(jq -r '.url' <<<"$result")" '{ok:true,repo:$repo,tag:$tag,url:$url}'
