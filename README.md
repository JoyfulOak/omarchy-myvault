# MyVault

This JoyfulOak fork builds on the upstream [anelcelik/omavault](https://github.com/anelcelik/omavault); upstream attribution and the MIT license are retained.

Back up your Omarchy setup -- bar/dock/search/theme settings, installed
plugins, Hyprland config, terminal configs, optional shell/editor dotfiles,
`~/Documents`, and package/app inventories -- to a folder tree, typically a
USB stick, and restore it on a fresh Omarchy install. Click the teal vault icon
on the bar; press `Esc` to close its panel.

This local fork adds **Documents** and **Installed apps** export/import
categories. App capture stores package inventories (Arch explicit packages,
foreign/AUR package names, Flatpak app IDs, and enabled Omarchy plugins), not
application binaries. After importing the inventory, review it and run
`bash ~/.config/omarchy/plugins/io.github.joyfuloak.myvault/bin/install-apps.sh`
from a terminal to reinstall supported packages; that helper asks for the exact
word `INSTALL` before it makes package-manager changes. Desktop applications
installed outside these package managers are not captured. Documents are
copied as files (including binary PDFs/images), without following symlinks;
the backup's 128 MiB limit still applies to the combined snapshot. For GitHub,
enter `owner/private-repository` in the panel; uploads create a release that
contains only the encrypted payload, and downloads fetch the latest MyVault
release into `~/Downloads/myvault-github/` for the usual passphrase and import
preview. Public repositories are rejected. Set up the GitHub CLI once with
`gh auth login`; this fork does not push code or backups automatically.

<p align="center">
  <img src="screenshots/export-tab.png" width="46%" alt="Export tab: category checklist, destination picker, required passphrase fields">
  <img src="screenshots/import-locked.png" width="46%" alt="Import tab: a detected backup, locked, waiting for its passphrase">
</p>

*(Mockups reproduced from the actual popup's QML/copy to illustrate the
layout -- not raw screen captures. Real file counts/sizes/drive names will
differ on your machine.)*

## Install

### Install from a Git repository

Use Omarchy's plugin installer with the URL of a Git repository that contains
this MyVault fork:

```bash
repo_url="https://github.com/OWNER/REPOSITORY.git"  # replace with this fork's URL
omarchy plugin add "$repo_url" --enable
omarchy plugin validate ~/.config/omarchy/plugins/io.github.joyfuloak.myvault
omarchy plugin list
omarchy restart shell
```

Replace the example URL with the repository where this fork is published. The
upstream `anelcelik/myvault` URL may install upstream code rather than the
Documents/apps/GitHub additions described here.

### Install from a local checkout

From the root of this repository, copy the plugin into Omarchy's user plugin
directory, then validate, enable, and restart the shell:

```bash
plugin_id=io.github.joyfuloak.myvault
plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
mkdir -p "$plugin_dir"
rsync -a --exclude='.git/' ./ "$plugin_dir/"
omarchy plugin validate "$plugin_dir"
omarchy plugin enable "$plugin_id"
omarchy restart shell
```

Confirm it is enabled with `omarchy plugin list`. To remove it later, run
`omarchy plugin remove io.github.joyfuloak.myvault`.

If this plugin was installed before, back up the existing plugin directory
before copying over it.

### Use the backup panel

After enabling the plugin, click its vault icon in the Omarchy bar. The open
panel is marked on the bar; press `Esc` to close it.

## Design

- **Always encrypted -- no plain-text option.** Every export stages the
  selected config, document, and inventory files in a private tmpfs folder,
  packs them into `payload.tar.gpg` using AES-256 via `gpg --symmetric`, then
  removes the plaintext staging tree. Nothing about a backup is readable off
  the destination without the passphrase: not file contents, category labels,
  or hostname. Non-text config files (icons, sqlite databases, compiled
  caches) are skipped; Documents preserves binaries such as PDFs and images.
  Skipped config binaries are listed in the encrypted README. The passphrase
  travels over stdin, never argv or disk, and is not remembered -- there is
  no recovery if it is lost.
- **Checksummed, not just copied.** Every export writes a `SHA256SUMS`
  covering every file (manifest.json included) before encrypting. Import
  decrypts, verifies the whole thing before touching anything on this
  machine, and refuses to restore if a checksum fails.
- **Non-destructive restore.** Anything an import is about to overwrite is
  copied first to `~/.local/state/myvault/pre-restore-<timestamp>/`.
  Restoring only adds/overwrites -- it never deletes existing files.
- **Decryption happens in memory, not on disk.** Import decrypts into a
  tmpfs temp dir (`$XDG_RUNTIME_DIR`, never the disk or the stick), wiped
  again once the popup closes or the restore attempt finishes.
- **You choose what's included, every time.** The Export tab lists every
  available category with a live file count/size: settings, plugins,
  Hyprland, terminals, Documents, and app/package inventories. Documents
  retain binary files; other categories remain text-only. The combined
  snapshot is capped at 128 MiB to bound RAM use while encrypting/decrypting.
  App/package lists are inventories, not installed program binaries.
- **In-popup folder browser**, not a native file-picker dialog -- a native
  GTK/portal `FolderDialog` reliably crashed the whole Quickshell process
  in testing (GVFS aborting inside libgtk-3's directory-monitor D-Bus
  call). "Browse..." instead lists real subdirectories via a small bash
  script + QML list, entirely in-process.

## Layout

```
bin/lib.sh                Category registry (source→snapshot path map) + shared helpers
bin/list-categories.sh    What's exportable on this machine, with live file counts
bin/list-drives.sh        Detected removable drives + any MyVault snapshots already on them
bin/list-dir.sh           Powers the in-popup folder browser
bin/export.sh             Builds a snapshot and encrypts it (stdin passphrase, required)
bin/inspect-snapshot.sh   Reads manifest.json + verifies SHA256SUMS, without touching the machine
bin/decrypt-snapshot.sh   Decrypts payload.tar.gpg into a tmpfs temp dir (stdin passphrase)
bin/cleanup-temp.sh       Removes a decrypt-snapshot.sh temp dir
bin/import.sh             Backs up existing files, then restores selected categories
bin/install-apps.sh       Reinstalls imported package inventories after explicit confirmation
bin/github-upload.sh      Uploads one encrypted payload to a private GitHub Release and verifies it
bin/github-download.sh    Downloads the latest MyVault Release payload from a private repo
```

Adding a new category means one entry in `lib.sh`'s `list_category_meta`
(the checkbox + description) and `category_entries` (the real path ->
snapshot path mapping) -- every script shares that one registry.
