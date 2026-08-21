#!/bin/bash
# Rebuilds vision-pro-operator-guide.html and Vision-Pro-Operator-Guide.pdf
# from build.py + figures.py + images/. Run from anywhere.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$DIR/build.py"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --no-sandbox \
  --run-all-compositor-stages-before-draw --virtual-time-budget=20000 \
  --no-pdf-header-footer \
  --print-to-pdf="$DIR/Vision-Pro-Operator-Guide.pdf" \
  "file://$DIR/vision-pro-operator-guide.html" 2>/dev/null
echo "PDF: $DIR/Vision-Pro-Operator-Guide.pdf"
