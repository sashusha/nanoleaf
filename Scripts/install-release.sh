#!/bin/sh
set -eu
release_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app="$release_dir/Nanoleaf.app"
/usr/bin/codesign --verify --strict "$app"
"$app/Contents/MacOS/nanoleaf" service enable
mkdir -p "$HOME/.local/bin"
ln -sfn "$HOME/Library/Application Support/nanoleaf/Nanoleaf.app/Contents/MacOS/nanoleaf" "$HOME/.local/bin/nanoleaf"
echo 'Installed. Ensure ~/.local/bin is on PATH. Run nanoleaf status to check permissions.'
