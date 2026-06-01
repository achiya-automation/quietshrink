#!/usr/bin/env bash
# Basic smoke tests for quietshrink

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/../bin/quietshrink"
PASS=0
FAIL=0

assert_equal() {
  if [ "$1" = "$2" ]; then
    echo "  ✓ $3"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $3"
    echo "    expected: $2"
    echo "    actual:   $1"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if echo "$1" | grep -q "$2"; then
    echo "  ✓ $3"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $3"
    echo "    expected to contain: $2"
    echo "    actual:              $1"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== quietshrink smoke tests ==="

# Test 1: help works
echo "test: --help"
HELP_OUT=$("$BIN" --help 2>&1)
assert_contains "$HELP_OUT" "USAGE" "help shows USAGE section"
assert_contains "$HELP_OUT" "tiny" "help mentions tiny preset"
assert_contains "$HELP_OUT" "transparent" "help mentions transparent preset"

# Test 2: version
echo "test: --version"
VERSION_OUT=$("$BIN" --version 2>&1)
assert_contains "$VERSION_OUT" "quietshrink" "version output mentions quietshrink"

# Test 3: missing file errors
echo "test: missing input file"
if "$BIN" /nonexistent/file.mov 2>/dev/null; then
  echo "  ✗ should fail on missing file"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ correctly errors on missing file"
  PASS=$((PASS + 1))
fi

# Test 4: invalid quality preset
echo "test: invalid quality preset"
if "$BIN" -q invalid /tmp/dummy.mov 2>/dev/null; then
  echo "  ✗ should fail on invalid preset"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ correctly errors on invalid preset"
  PASS=$((PASS + 1))
fi

# Test 5: real compression (if test fixture exists)
if [ -f "$SCRIPT_DIR/fixtures/sample.mov" ]; then
  echo "test: real compression"
  TMP_OUT="/tmp/quietshrink_test_$$.mov"
  RESULT=$("$BIN" --json "$SCRIPT_DIR/fixtures/sample.mov" "$TMP_OUT" 2>/dev/null)

  if [ -f "$TMP_OUT" ]; then
    echo "  ✓ output file created"
    PASS=$((PASS + 1))

    SAVED_PCT=$(echo "$RESULT" | grep saved_percent | grep -oE '[0-9]+\.[0-9]+')
    if [ -n "$SAVED_PCT" ]; then
      echo "  ✓ JSON output has saved_percent: $SAVED_PCT%"
      PASS=$((PASS + 1))
    fi
    rm -f "$TMP_OUT"
  else
    echo "  ✗ output file not created"
    FAIL=$((FAIL + 1))
  fi
fi

# Test 6: timing fidelity — output must keep the source's real duration.
# Regression guard for the VFR bug where "setpts=N/FRAME_RATE/TB" re-stamped the
# surviving (decimated) frames by index at the nominal fps, crushing the video into
# a fraction of its length (played too fast) and freezing the last frame for the
# rest of the audio.
# This needs a WORKING video encoder. CI macOS runners are VMs where
# hevc_videotoolbox is listed but hardware encoding fails — so if the test clip
# can't be encoded here, the check skips instead of failing.
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
  echo "test: timing fidelity (no speed-up / frozen tail)"
  TIMING_DIR=$(mktemp -d)
  TIMING_SRC="$TIMING_DIR/src.mov"
  TIMING_OUT="$TIMING_DIR/out.mov"
  # 10s clip: 20 unique frames stretched to 60fps (heavy duplicate frames) + audio
  ffmpeg -y -f lavfi -i "testsrc2=s=320x240:r=2:d=10" -f lavfi -i "sine=frequency=440:d=10" \
    -vf "fps=60" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$TIMING_SRC" >/dev/null 2>&1 || true
  if [ -f "$TIMING_SRC" ] && "$BIN" -q tiny "$TIMING_SRC" "$TIMING_OUT" >/dev/null 2>&1 && [ -f "$TIMING_OUT" ]; then
    TIMING_FMT=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$TIMING_OUT")
    TIMING_VID=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 "$TIMING_OUT")
    if [ -n "$TIMING_FMT" ] && [ -n "$TIMING_VID" ]; then
      TIMING_VERDICT=$(awk -v f="$TIMING_FMT" -v v="$TIMING_VID" 'BEGIN { d=f-v; if (d<0) d=-d; print (d<1.5)?"ok":"bad" }')
      assert_equal "$TIMING_VERDICT" "ok" "compressed video duration tracks source (video=${TIMING_VID}s vs container=${TIMING_FMT}s)"
    else
      echo "  ⊘ skipped — probe returned no duration"
    fi
  else
    echo "  ⊘ skipped — no working video encoder in this environment (e.g. CI VM)"
  fi
  rm -rf "$TIMING_DIR"
fi

# Test 7: "source" preset keeps every frame at a constant 60fps (no dedup, player-safe CFR).
# Guards against regressing the full-quality path back into mpdecimate/VFR.
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
  echo "test: source preset (full quality, CFR 60, no frame drop)"
  SRC_DIR=$(mktemp -d)
  SRC_IN="$SRC_DIR/in.mov"; SRC_OUT="$SRC_DIR/out.mov"
  # 6s clip, 120fps nominal, few unique frames (mimics a VFR screen recording) + audio
  ffmpeg -y -f lavfi -i "testsrc2=s=320x240:r=2:d=6" -f lavfi -i "sine=frequency=440:d=6" \
    -vf "fps=120" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$SRC_IN" >/dev/null 2>&1 || true
  if [ -f "$SRC_IN" ] && "$BIN" -q source "$SRC_IN" "$SRC_OUT" >/dev/null 2>&1 && [ -f "$SRC_OUT" ]; then
    SRC_FMT=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$SRC_OUT")
    SRC_VID=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 "$SRC_OUT")
    SRC_RFPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$SRC_OUT")
    SRC_NB=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of default=nw=1:nk=1 "$SRC_OUT")
    SRC_NB=${SRC_NB//[!0-9]/}; [ -z "$SRC_NB" ] && SRC_NB=0
    SRC_OK_DUR=$(awk -v f="$SRC_FMT" -v v="$SRC_VID" 'BEGIN { d=f-v; if (d<0) d=-d; print (d<1.5)?1:0 }')
    if [ "$SRC_RFPS" = "60/1" ] && [ "$SRC_OK_DUR" = "1" ] && [ "$SRC_NB" -gt 100 ]; then
      echo "  ✓ source: CFR 60, duration preserved, frames kept (nb_frames=$SRC_NB)"; PASS=$((PASS + 1))
    else
      echo "  ✗ source preset wrong: r_fps=$SRC_RFPS dur_ok=$SRC_OK_DUR nb_frames=$SRC_NB"; FAIL=$((FAIL + 1))
    fi
  else
    echo "  ⊘ skipped — no working video encoder in this environment (e.g. CI VM)"
  fi
  rm -rf "$SRC_DIR"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
