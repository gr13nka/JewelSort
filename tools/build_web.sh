#!/usr/bin/env bash
# build_web.sh
# One-shot web build for JewelSort:
#   1. Pack game sources into a .love zip (skipping .git, build, tools cache).
#   2. Run love.js (Davidobot fork via npx) to produce build/web/.
#   3. Apply tools/patch_web.sh to inject the Yandex Games SDK bridge.
#
# Usage:
#   ./tools/build_web.sh
#
# Output: build/web/ — ready to zip and upload to Yandex Games console.

set -euo pipefail
cd "$(dirname "$0")/.."

LOVE_TMP="$(mktemp -d)/jewelsort.love"
trap 'rm -f "$LOVE_TMP"; rmdir "$(dirname "$LOVE_TMP")" 2>/dev/null || true' EXIT

echo "build_web: packing .love archive..."
zip -qr "$LOVE_TMP" \
    main.lua conf.lua \
    src/ levels/ assets/ locale/ \
    tools/make_samples.lua \
    -x '*.pyc' -x '__pycache__/*'

rm -rf build/web

echo "build_web: running love.js (compatibility mode for Yandex)..."
# --compatibility disables the SharedArrayBuffer path. Yandex's draft
# host doesn't send the COOP+COEP headers that modern browsers now
# require before exposing SharedArrayBuffer, so without this flag the
# game.js boot throws "SharedArrayBuffer is not defined" at Love(Module).
npx --yes love.js "$LOVE_TMP" build/web \
    --title "JewelSort" \
    --memory 67108864 \
    --compatibility >/dev/null

echo "build_web: patching for Yandex Games..."
./tools/patch_web.sh

size_mb=$(du -sm build/web | cut -f1)
echo "build_web: done. build/web/ is ${size_mb} MB."
echo "build_web: to serve locally: npx http-server build/web -p 8080 -o"
