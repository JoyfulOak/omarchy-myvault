#!/bin/bash
# Outputs a JSON array describing every exportable category available on
# this machine, with a live file/byte count for each so the GUI checkbox
# list can show real numbers before the user commits to an export.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
. ./lib.sh

result="[]"
while IFS=$'\t' read -r id label desc defaultOn; do
  [ -z "$id" ] && continue
  files=0
  bytes=0
  packages=0
  while IFS=$'\t' read -r src rel kind extraExclude; do
    [ -z "$src" ] && continue
    if [ "$kind" = "file" ]; then
      [ -f "$src" ] || continue
      files=$((files + 1))
      bytes=$((bytes + $(stat -c%s -- "$src" 2>/dev/null || echo 0)))
    else
      [ -d "$src" ] || continue
      # Name-based excludes only, for a fast estimate -- the binary-content
      # sniff pass only runs during a real export, not this preview count.
      stats=$(rsync -a --dry-run --stats "${BINARY_RSYNC_EXCLUDES[@]}" $extraExclude "$src/" /tmp/myvault-count-target-unused/ 2>/dev/null)
      n=$(awk -F': ' '/Number of regular files transferred/ {gsub(",","",$2); print $2}' <<<"$stats")
      b=$(awk -F': ' '/Total transferred file size/ {gsub(/[, bytes]/,"",$2); print $2}' <<<"$stats")
      files=$((files + ${n:-0}))
      bytes=$((bytes + ${b:-0}))
    fi
  done < <(category_entries "$id")

  if [ "$id" = "documents" ]; then
    files=$(find "$HOME/Documents" -type f 2>/dev/null | wc -l)
    bytes=$(find "$HOME/Documents" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
  elif [ "$id" = "apps" ]; then
    if command -v pacman >/dev/null 2>&1; then
      packages=$((packages + $(pacman -Qqen 2>/dev/null | wc -l) + $(pacman -Qqem 2>/dev/null | wc -l)))
    fi
    if command -v flatpak >/dev/null 2>&1; then
      packages=$((packages + $(flatpak list --app --columns=application 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l)))
    fi
    files=1
  fi

  entry=$(jq -n --arg id "$id" --arg label "$label" --arg desc "$desc" \
    --argjson defaultOn "$( [ "$defaultOn" = "1" ] && echo true || echo false )" \
    --argjson files "$files" --argjson bytes "$bytes" --argjson packages "$packages" \
    '{id:$id, label:$label, description:$desc, defaultOn:$defaultOn, fileCount:$files, bytes:$bytes, packageCount:$packages}')
  result=$(jq --argjson e "$entry" '. + [$e]' <<<"$result")
done < <(list_category_meta)

echo "$result"
