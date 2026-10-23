#!/bin/zsh
# 執行 UI 測試（合成訊號輸入），把測試產生的截圖匯出到 docs/screenshots/。
# 用法：scripts/export-screenshots.sh ["iPhone 18 Pro"]
set -euo pipefail

cd "$(dirname "$0")/.."
DEVICE="${1:-iPhone 18 Pro}"
RESULT="build/Screenshots.xcresult"
EXPORT="build/screenshot-export"
OUTPUT="docs/screenshots"

rm -rf "$RESULT" "$EXPORT"
xcodebuild test \
  -project PitchCoach.xcodeproj \
  -scheme PitchCoach \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:PitchCoachUITests \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "$RESULT" \
  -quiet

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EXPORT" > /dev/null

# manifest 中的建議檔名形如「01-tuner_0_<UUID>.png」，取底線前的部分作為檔名
python3 -I - "$EXPORT" "$OUTPUT" <<'PY'
import json, shutil, sys
from pathlib import Path
export, output = Path(sys.argv[1]), Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
for test in json.loads((export / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        name = attachment["suggestedHumanReadableName"].split("_")[0] + ".png"
        shutil.copy(export / attachment["exportedFileName"], output / name)
        print(output / name)
PY
