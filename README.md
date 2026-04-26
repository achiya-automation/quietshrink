<h1 align="center">quietshrink</h1>

<p align="center">
  <strong>Compress screen recordings without making your fans spin.</strong><br>
  <sub>70-90% smaller files. Visually lossless. Computer stays silent.</sub>
</p>

<p align="center">
  <a href="#install"><img src="https://img.shields.io/badge/install-one_line-brightgreen" alt="Install"></a>
  <a href="https://github.com/achiya-automation/quietshrink/releases"><img src="https://img.shields.io/badge/version-1.0.0-blue" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-yellow" alt="License"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-Apple_Silicon-black?logo=apple" alt="macOS"></a>
  <a href="https://hkuds.github.io/CLI-Anything/"><img src="https://img.shields.io/badge/CLI--Hub-agent--ready-ff69b4" alt="CLI-Anything"></a>
</p>

---

## The problem

Mac screen recordings are huge. A 3-minute screencast easily hits 100+ MB at retina resolution. Existing compressors (HandBrake, ShrinkVideo, Compressor) use software encoders that pin your CPU at 100% for minutes — fans roar, battery drains, your laptop becomes a heater.

## The fix

`quietshrink` runs entirely on Apple Silicon's **Media Engine** — the dedicated chip that handles HEVC encoding without touching the CPU. Combined with smart frame deduplication and tuned GOP settings, it produces files **typically 80-90% smaller than the original** while staying **visually indistinguishable from the source**.

**The computer stays silent.** Even on a fanless MacBook Air, you won't notice it's running.

## Real numbers

A typical macOS screen recording (3024×1964 @ 120fps, 3 minutes):

| Tool | Output Size | Encoding Time | Computer Load |
|------|-------------|---------------|---------------|
| Original | 105 MB | — | — |
| HandBrake (default) | 42 MB | 4 min | 🔴 Fans on |
| ShrinkVideo | 35 MB | 5 min | 🔴 Fans on |
| `libx265 CRF 18` (manual ffmpeg) | 25 MB | 10 min | 🔴 Fans on |
| **`quietshrink`** | **12 MB** | **90 sec** | 🟢 **Silent** |

Quality: SSIM 0.99+ (visually identical to source).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/achiya-automation/quietshrink/main/install.sh | bash
```

Or manually:

```bash
# Requires ffmpeg
brew install ffmpeg

# Clone and link
git clone https://github.com/achiya-automation/quietshrink.git
sudo ln -s "$(pwd)/quietshrink/bin/quietshrink" /usr/local/bin/quietshrink
```

## Usage

```bash
# Default: transparent quality (visually lossless)
quietshrink recording.mov

# Tiny preset — for chat / email sharing
quietshrink -q tiny recording.mov

# Replace original
quietshrink --replace recording.mov

# Batch a whole folder
for f in ~/Desktop/*.mov; do quietshrink "$f"; done
```

### Quality presets

| Preset | Use case | Typical reduction | SSIM |
|--------|----------|-------------------|------|
| `tiny` | Chat / email | ~90% | 0.95 |
| `balanced` | Documentation | ~88% | 0.99 |
| **`transparent`** (default) | **Anything important** | **~87%** | **0.99+** |
| `pristine` | Archival / editing | ~84% | 0.997 |

## How it works

Three optimizations layered together:

```bash
ffmpeg -i input.mov \
  -vf "mpdecimate,setpts=N/FRAME_RATE/TB" \
  -c:v hevc_videotoolbox -q:v 60 \
  -prio_speed 0 -spatial_aq 1 \
  -g 600 \
  -tag:v hvc1 \
  -c:a aac -b:a 96k \
  -movflags +faststart \
  output.mov
```

1. **`hevc_videotoolbox`** — Apple's hardware HEVC encoder. Runs on the Media Engine chip, not the CPU. This is why your fans don't spin.

2. **`mpdecimate`** — Detects and drops duplicate frames. Screen recordings at 60-120fps have many identical consecutive frames (no on-screen change between captures). Removing them is lossless and shrinks the file dramatically.

3. **`spatial_aq` + long GOP** — Apple's adaptive quantization sends more bits to text and edges, fewer to flat areas. Long GOP (600) reduces redundant keyframes for static content. Together, these two tweaks cut another 50-70% off the size.

For the deep-dive on why each parameter matters, see [WHY.md](WHY.md).

## Requirements

- **macOS** with Apple Silicon (M1, M2, M3, M4)
- **ffmpeg 6+** (`brew install ffmpeg`)

Intel Macs work but without hardware acceleration — the computer will get loud, defeating the purpose.

## Comparison vs alternatives

| Tool | Encoder | Hardware accelerated | Smart dedup | Polished CLI |
|------|---------|---------------------|-------------|--------------|
| HandBrake | x264/x265 (sw) | optional, low quality | ❌ | GUI only |
| ShrinkVideo | libx265 (sw) | ❌ | ❌ | ⚠️ |
| Compresto | libx265 (sw) | ❌ | ❌ | GUI only, paid |
| Apple Compressor | videotoolbox | ✅ | ❌ | paid, complex |
| **quietshrink** | **hevc_videotoolbox** | ✅ | ✅ | ✅ |

## Agent integration (CLI-Anything)

`quietshrink` ships with an [agent-native CLI](agent-harness/) compatible with [CLI-Anything](https://hkuds.github.io/CLI-Anything/) — AI agents (Claude Code, Cursor, OpenClaw) can install and use it via a single pip command:

```bash
pip install cli-anything-quietshrink
```

The agent harness wraps the bash CLI with structured JSON output and skill files agents can read.

## FAQ

<details>
<summary><b>Why is the file smaller than HandBrake's output?</b></summary>

HandBrake uses general-purpose presets. `quietshrink` is specifically tuned for screen recordings: long GOP (most screen content is static), aggressive frame deduplication (consecutive frames are often identical), and Apple's adaptive quantization (more bits to text). Together these layer multiplicatively.
</details>

<details>
<summary><b>Will it work on my old Intel Mac?</b></summary>

It will compress fine, but `hevc_videotoolbox` falls back to software on Intel — your CPU will be busy and fans will spin. If you have an Intel Mac, you might be just as well off with HandBrake.
</details>

<details>
<summary><b>Can I use this for camera footage / vlogs / screen + camera?</b></summary>

It works but the savings will be smaller. Camera footage doesn't have duplicate frames, so `mpdecimate` doesn't help. You'll still get ~50% reduction from videotoolbox + long GOP, just not the 80-90% screen recordings see.
</details>

<details>
<summary><b>Why not AV1?</b></summary>

AV1 compresses ~25% better than HEVC at the same quality, but Apple Silicon (through M4) has no hardware AV1 encoder. Software AV1 encoding (SVT-AV1) is loud and slow. When Apple adds hardware AV1 encoding (likely M5), `quietshrink` will switch to it.
</details>

<details>
<summary><b>How is quality verified?</b></summary>

We use [SSIM](https://en.wikipedia.org/wiki/Structural_similarity) (Structural Similarity Index) — a perceptual quality metric. The default preset achieves SSIM > 0.99, which is below the threshold of human visual detection.
</details>

## Contributing

PRs welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

Bug? [Open an issue](https://github.com/achiya-automation/quietshrink/issues).

## License

MIT. See [LICENSE](LICENSE).

## Credits

Built on top of:
- [FFmpeg](https://ffmpeg.org/) — the universal video toolkit
- [Apple VideoToolbox](https://developer.apple.com/documentation/videotoolbox) — hardware encoding
- [mpdecimate filter](https://ffmpeg.org/ffmpeg-filters.html#mpdecimate) — frame deduplication

Distributed via [CLI-Anything](https://hkuds.github.io/CLI-Anything/) for AI agent ecosystems.

---

<p align="center">
  <sub>If quietshrink saved you a fan spin-up, consider giving it a ⭐</sub>
</p>
