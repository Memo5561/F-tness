#!/bin/bash
# Ad-hoc probe render: PROBE=id@frame[.frac],... [BG=light] tool/probe.sh -> out/probe.png
cd "$(dirname "$0")/.."
export PATH=/opt/sdk/flutter/bin:$PATH
flutter test --update-goldens test/probe_test.dart 2>&1 | grep -E "Error|error:|passed|failed" | head -20
