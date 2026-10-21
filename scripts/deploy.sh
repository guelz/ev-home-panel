#!/usr/bin/env bash
# Copy the panel to Home Assistant's ESPHome config dir (e.g. a Samba mount of
# /config/esphome) and the icons to /config/www/ev-panel/icons (served at
# /local/ev-panel/icons). Then build + flash from the HA ESPHome dashboard.
# CIFS-safe: no time/perm preserve.
#
# usage: deploy.sh <device-basename> [target-basename]
#   EV_PANEL_DEPLOY_DIR  target esphome dir (default: the author's Samba mount)
#   target-basename      file name on the HA side, if it differs from the repo's
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST="${EV_PANEL_DEPLOY_DIR:-/root/shared/ha-smb-share/esphome}"
dev="${1:?usage: deploy.sh <device-basename> [target-basename]}"
target="${2:-$dev}"

rm -rf "$DST/ev-panel"
cp -r "$SRC/ev-panel" "$DST/ev-panel"
mkdir -p "$DST/_fonts"
cp -f "$SRC/_fonts/"*.ttf "$DST/_fonts/"      # don't wipe _fonts: other devices may use it
cp "$SRC/$dev.yaml" "$DST/$target.yaml"
echo "deployed $dev -> $DST/$target.yaml"

# Icons to HA www/. rm -rf first: a Samba share is case-INSENSITIVE, and cp -r
# over existing files fails there ("File exists") — so clear the dir to avoid
# stale/renamed leftovers.
WWW="$DST/../www/ev-panel/icons"
rm -rf "$WWW"
mkdir -p "$WWW"
cp -r "$SRC/ev-panel/icons/." "$WWW/"
echo "synced icons -> $WWW"
