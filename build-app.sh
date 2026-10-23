#!/bin/bash
# Compila, monta e instala a Ava em /Applications. Uso: ./build-app.sh && open /Applications/Ava.app
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=.build/Ava.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ava "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c "Add :AvaBackendDir string $(pwd)/backend" "$APP/Contents/Info.plist"
cp -R .build/release/*.bundle "$APP/Contents/Resources/" 2>/dev/null || true  # recursos das bibliotecas
codesign --force -s - "$APP"
osascript -e 'tell application id "io.github.ava-voice-assistant" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/Ava.app
ditto "$APP" /Applications/Ava.app
echo "Pronto: /Applications/Ava.app"
