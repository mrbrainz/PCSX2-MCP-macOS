#!/bin/bash
# Build PCSX2 v2.8.2 with the DebugServer patch on macOS.
#
# Needs: full Xcode selected (xcode-select -p -> Xcode.app), Homebrew cmake,
# ninja and nasm. PCSX2 on macOS is x86_64 only and runs under Rosetta.
# First run takes ~15 min on an M-series Mac (Qt and friends build from source), ~500 MB.
#
# Usage: ./build-macos.sh [work dir]   (default: ./pcsx2-build)
set -euo pipefail

PCSX2_TAG=v2.8.2
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${1:-$HERE/pcsx2-build}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

case "$(xcode-select -p)" in
	*Xcode*.app*) ;;
	*) echo "Full Xcode must be selected: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; exit 1 ;;
esac
xcrun -f metal > /dev/null || { echo "Metal toolchain missing: install it from Xcode > Settings > Components"; exit 1; }
for t in cmake ninja nasm git; do
	command -v "$t" > /dev/null || { echo "$t not found (brew install $t)"; exit 1; }
done

if [ ! -d "$WORK/src" ]; then
	git clone --depth 1 --branch "$PCSX2_TAG" https://github.com/PCSX2/pcsx2.git "$WORK/src"
	git -C "$WORK/src" apply "$HERE"/pcsx2-patch/*.patch
fi

if [ ! -f "$WORK/deps/.done" ]; then
	mkdir -p "$WORK/deps-work"
	(cd "$WORK/deps-work" && bash "$WORK/src/.github/workflows/scripts/macos/build-dependencies.sh" "$WORK/deps")
	touch "$WORK/deps/.done"
fi

cmake -S "$WORK/src" -B "$WORK/src/build" -G Ninja \
	-DCMAKE_PREFIX_PATH="$WORK/deps" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_OSX_ARCHITECTURES=x86_64 \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
	-DDISABLE_ADVANCE_SIMD=ON \
	-DUSE_LINKED_FFMPEG=ON \
	-DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON
# macdeployqt's own signing step fails on ad-hoc builds; we re-sign below.
if ! ninja -C "$WORK/src/build" 2>&1 | tee "$WORK/build.log"; then :; fi
if grep -q "error:" "$WORK/build.log" && ! grep -q "Codesign signing error" "$WORK/build.log"; then
	echo "Build failed, see $WORK/build.log"; exit 1
fi

APP="$WORK/src/build/pcsx2-qt/PCSX2.app"
codesign --force --deep -s - "$APP"
codesign --verify "$APP"
echo
echo "Built: $APP"
echo "Launch it, boot a game; the debug server listens on 127.0.0.1:21512."
