#!/bin/bash
# Regenerate PNGs via golden files.
# Usage: tool/render.sh [dark|light|strips|thumbs|hires]   (no arg = dark+light+strips+thumbs)
#        IDS=cal_front_lever,cal_handstand tool/render.sh hires   (800px cells)
cd "$(dirname "$0")/.."
export PATH=/opt/sdk/flutter/bin:$PATH
if [ -n "$1" ]; then export ONLY="$1"; else unset ONLY; fi
flutter test --update-goldens test/render_sheets_test.dart 2>&1 | grep -E "error|Error|Exception|failed|passed|\.dart:[0-9]+" | head -40
