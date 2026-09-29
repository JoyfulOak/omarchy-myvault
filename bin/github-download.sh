#!/usr/bin/env bash
# Fetch the latest MyVault encrypted-release asset from a private repository.
set -euo pipefail
repo="${1:-}"
dest="${2:-}"
fail() { jq -n --arg error "$1" '{ok:false,error:$error}'; exit 1; }
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Repository must be owner/name.'
[[ -n "$dest" ]] || fail 'Choose a download folder.'
mkdir -p "$dest" 2>/dev/null || fail 'Could not create the download folder.'
[[ -d "$dest" && -w "$dest" ]] || fail 'Download folder is not writable.'
command -v gh >/dev/null 2>&1 || fail 'GitHub CLI (gh) is required.'
gh auth status >/dev/null 2>&1 || fail 'Authenticate GitHub CLI first with: gh auth login'
private=$(gh repo view "$repo" --json isPrivate --jq '.isPrivate' 2>/dev/null) || fail 'Could not read GitHub repository; check owner/name and access.'
[[ "$private" == true ]] || fail 'Refusing to download backup assets from a public repository.'
releases=$(gh release list --repo "$repo" --limit 100 --json tagName,isDraft,isPrerelease,publishedAt 2>/dev/null) || fail 'Could not list GitHub releases.'
tag=$(jq -r '[.[] | select((.tagName | startswith("myvault-")) and (.isDraft == false) and (.isPrerelease == false))] | sort_by(.publishedAt) | last | .tagName // empty' <<<"$releases")
[[ -n "$tag" ]] || fail 'No published MyVault backup release found.'
out="$dest/$tag"
mkdir -p "$out"
gh release download "$tag" --repo "$repo" --pattern payload.tar.gpg --dir "$out" >/dev/null 2>&1 || fail 'Could not download the latest encrypted backup.'
payload="$out/payload.tar.gpg"
[[ -f "$payload" && ! -L "$payload" && -s "$payload" ]] || fail 'Downloaded release did not contain a valid encrypted payload.'
jq -n --arg repo "$repo" --arg tag "$tag" --arg path "$out" '{ok:true,repo:$repo,tag:$tag,path:$path}'
