#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${XDG_RUNTIME_DIR:?Run this test from a graphical user session}"
root=$(mktemp -d "$XDG_RUNTIME_DIR/myvault-test.XXXXXX")
chmod 700 "$root"
trap 'rm -rf "$root"' EXIT
source_home="$root/source-home"
target_home="$root/target-home"
runtime="$root/runtime"
dest="$root/destination"
mockbin="$root/mockbin"
mkdir -p "$source_home/Documents/nested" "$source_home/.config/hypr" "$target_home/Documents" "$runtime" "$dest" "$mockbin"
chmod 700 "$runtime"

cat >"$mockbin/pacman" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  -Qqen) printf 'firefox\nkitty\n' ;;
  -Qqem) printf 'brave-bin\n' ;;
  *) exit 2 ;;
esac
MOCK
cat >"$mockbin/flatpak" <<'MOCK'
#!/usr/bin/env bash
[ "$1 $2 $3" = 'list --app --columns=application' ] && printf 'org.mozilla.firefox\n' || exit 2
MOCK
cat >"$mockbin/omarchy" <<'MOCK'
#!/usr/bin/env bash
[ "$1 $2 $3" = 'plugin list --json' ] && printf '[{"id":"example.plugin","enabled":true}]' || exit 2
MOCK
cat >"$mockbin/hostname" <<'MOCK'
#!/usr/bin/env bash
printf 'test-host\n'
MOCK
cat >"$mockbin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  auth) [[ "${GH_MOCK_AUTH:-}" == 1 ]] ;;
  repo) [[ "$2" == view ]] && printf '%s\n' "${GH_MOCK_PRIVATE:-false}" ;;
  release)
    case "$2" in
      create) : >"$GH_MOCK_UPLOAD_MARKER" ;;
      view) printf '{"url":"https://github.com/example/private/releases/tag/mock","assets":[{"name":"payload.tar.gpg"}]}\n' ;;
      list) printf '[{"tagName":"myvault-20260928120000","isDraft":false,"isPrerelease":false,"publishedAt":"2026-09-28T12:00:00Z"}]\n' ;;
      download)
        shift 3
        out=""
        while (($#)); do [[ "$1" == --dir ]] && { out="$2"; shift 2; continue; }; shift; done
        mkdir -p "$out"
        printf 'encrypted-mock' >"$out/payload.tar.gpg"
        ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$mockbin"/*

python3 - "$source_home" <<'PY'
import pathlib, sys
home = pathlib.Path(sys.argv[1])
(home / 'Documents/nested/scan.pdf').write_bytes(b'%PDF-1.7\x00binary sample\xff')
(home / 'Documents/readme.txt').write_text('portable document\\n')
(home / '.config/hypr/hyprland.conf').write_text('exec-once = true\\n')
(home / 'outside.txt').write_text('must not be followed')
(home / 'Documents/outside-link').symlink_to(home / 'outside.txt')
PY

common_env=(env "HOME=$source_home" "XDG_RUNTIME_DIR=$runtime" "PATH=$mockbin:$PATH")
"${common_env[@]}" bash "$repo/bin/list-categories.sh" >"$root/categories.json"
jq -e '.[] | select(.id=="documents" and .fileCount==2)' "$root/categories.json" >/dev/null
jq -e '.[] | select(.id=="apps" and .packageCount==4)' "$root/categories.json" >/dev/null
jq -e '.[] | select(.id=="hypr")' "$root/categories.json" >/dev/null

export_json=$(printf 'test-passphrase\n' | "${common_env[@]}" bash "$repo/bin/export.sh" hypr,documents,apps "$dest" new)
snapshot=$(jq -r '.path' <<<"$export_json")
jq -e '.ok == true and .encrypted == true and ([.categories[].id] | sort == ["apps","documents","hypr"])' <<<"$export_json" >/dev/null

decrypt_json=$(printf 'test-passphrase\n' | "${common_env[@]}" bash "$repo/bin/decrypt-snapshot.sh" "$snapshot")
plain=$(jq -r '.tempDir' <<<"$decrypt_json")
inspect_json=$("${common_env[@]}" bash "$repo/bin/inspect-snapshot.sh" "$plain")
jq -e '.ok == true and .checksumOk == true and ([.manifest.categories[].id] | sort == ["apps","documents","hypr"])' <<<"$inspect_json" >/dev/null
cmp "$source_home/Documents/nested/scan.pdf" "$plain/Documents/nested/scan.pdf"
cmp "$source_home/Documents/readme.txt" "$plain/Documents/readme.txt"
test ! -e "$plain/Documents/outside-link"
jq -e '.counts.archExplicit == 2 and .counts.archForeign == 1 and .counts.flatpakApps == 1' "$plain/app-inventory/inventory.json" >/dev/null

touch "$target_home/Documents/keep.txt"
target_env=(env "HOME=$target_home" "XDG_RUNTIME_DIR=$runtime" "PATH=$mockbin:$PATH")
"${target_env[@]}" bash "$repo/bin/import.sh" "$plain" hypr,documents,apps >"$root/import.json"
jq -e '.ok == true and ([.categories[].id] | sort == ["apps","documents","hypr"])' "$root/import.json" >/dev/null
cmp "$source_home/Documents/nested/scan.pdf" "$target_home/Documents/nested/scan.pdf"
cmp "$source_home/.config/hypr/hyprland.conf" "$target_home/.config/hypr/hyprland.conf"
test -f "$target_home/Documents/keep.txt"
test -f "$target_home/.local/state/myvault/apps/arch-explicit.txt"
cmp "$target_home/.local/state/myvault/apps/arch-explicit.txt" "$plain/app-inventory/arch-explicit.txt"

# App installer must require an explicit confirmation and perform no install on decline.
printf 'no\n' | env "HOME=$target_home" "PATH=$mockbin:$PATH" bash "$repo/bin/install-apps.sh" >"$root/install-cancel.txt"
grep -q Cancelled "$root/install-cancel.txt"

# GitHub helpers are exercised against a mock CLI; no remote writes occur.
export GH_MOCK_AUTH=1 GH_MOCK_PRIVATE=true GH_MOCK_UPLOAD_MARKER="$root/gh-uploaded"
gh_env=(env "HOME=$source_home" "PATH=$mockbin:$PATH" "GH_MOCK_AUTH=$GH_MOCK_AUTH" "GH_MOCK_PRIVATE=$GH_MOCK_PRIVATE" "GH_MOCK_UPLOAD_MARKER=$GH_MOCK_UPLOAD_MARKER")
gh_upload=$("${gh_env[@]}" bash "$repo/bin/github-upload.sh" example/private "$snapshot")
jq -e '.ok == true and .repo == "example/private" and (.url | startswith("https://github.com/"))' <<<"$gh_upload" >/dev/null
test -f "$GH_MOCK_UPLOAD_MARKER"
if env HOME="$source_home" PATH="$mockbin:$PATH" GH_MOCK_AUTH=1 GH_MOCK_PRIVATE=false GH_MOCK_UPLOAD_MARKER="$root/should-not-upload" bash "$repo/bin/github-upload.sh" example/public "$snapshot" >"$root/public.json"; then
  printf 'Public-repository upload was not rejected.\n' >&2; exit 1
fi
jq -e '.ok == false and (.error | contains("public"))' "$root/public.json" >/dev/null
test ! -e "$root/should-not-upload"
gh_download=$("${gh_env[@]}" bash "$repo/bin/github-download.sh" example/private "$root/downloads")
download_path=$(jq -r '.path' <<<"$gh_download")
jq -e '.ok == true and .tag == "myvault-20260928120000"' <<<"$gh_download" >/dev/null
test -s "$download_path/payload.tar.gpg"

"${common_env[@]}" bash "$repo/bin/cleanup-temp.sh" "$plain"
printf 'PASS: Documents/app round-trip, encryption/checksums, install confirmation, private-only GitHub upload/download mock, public-repo refusal.\n'
