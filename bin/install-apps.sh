#!/usr/bin/env bash
# Reinstall package names recorded by MyVault after the inventory was imported.
# This is deliberately separate from file restore and requires an explicit
# confirmation; it invokes the destination system's package managers.
set -euo pipefail

inventory="${1:-$HOME/.local/state/myvault/apps}"
[ -d "$inventory" ] || { printf 'No imported app inventory at %s\n' "$inventory" >&2; exit 1; }

read_list() {
  local file="$1" p
  local -n out="$2"
  out=()
  [ -f "$file" ] || return 0
  while IFS= read -r p || [ -n "$p" ]; do
    [ -z "$p" ] && continue
    [[ "$p" =~ ^[A-Za-z0-9][A-Za-z0-9@._+-]*$ ]] || { printf 'Unsafe package identifier rejected: %q\n' "$p" >&2; return 1; }
    out+=("$p")
  done < "$file"
}

read_list "$inventory/arch-explicit.txt" repo
read_list "$inventory/arch-foreign.txt" foreign
read_list "$inventory/flatpak-apps.txt" flatpaks

printf 'Repository packages: %d\nForeign/AUR packages: %d\nFlatpak apps: %d\n' "${#repo[@]}" "${#foreign[@]}" "${#flatpaks[@]}"
printf 'This installs packages on this computer; review the inventory before proceeding. Type INSTALL to continue: '
IFS= read -r answer
[ "$answer" = INSTALL ] || { printf 'Cancelled.\n'; exit 0; }

if ((${#repo[@]})); then
  command -v pacman >/dev/null 2>&1 || { printf 'pacman is required for the Arch repository list.\n' >&2; exit 1; }
  sudo pacman -S --needed -- "${repo[@]}"
fi
if ((${#foreign[@]})); then
  helper=""
  command -v yay >/dev/null 2>&1 && helper=yay
  [ -n "$helper" ] || { command -v paru >/dev/null 2>&1 && helper=paru; }
  [ -n "$helper" ] || { printf 'Install yay or paru first to restore foreign/AUR packages.\n' >&2; exit 1; }
  "$helper" -S --needed -- "${foreign[@]}"
fi
if ((${#flatpaks[@]})); then
  command -v flatpak >/dev/null 2>&1 || { printf 'flatpak is required for the Flatpak list.\n' >&2; exit 1; }
  flatpak install --assumeyes flathub "${flatpaks[@]}"
fi
printf 'Package restore commands completed. Some packages may not exist in current repositories or be compatible with this system.\n'
