#!/bin/bash
# render.sh <layout> <width> <height> <out.png>
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --allow-file-access-from-files --virtual-time-budget=4000 \
  --window-size="$2,$3" --screenshot="$dir/raw-$1.png" "file://$dir/banner.html?layout=$1" >/dev/null 2>&1
# Apple rejects alpha channels: flatten to RGB.
uv run -q --with pillow python -c "from PIL import Image; Image.open('$dir/raw-$1.png').convert('RGB').save('$4')"
rm -f "$dir/raw-$1.png"
