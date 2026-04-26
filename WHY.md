# Why quietshrink?

A deep-dive on the engineering decisions.

## The full command, annotated

```bash
ffmpeg -i input.mov \
  -vf "mpdecimate,setpts=N/FRAME_RATE/TB" \    # 1. drop duplicate frames
  -c:v hevc_videotoolbox -q:v 60 \             # 2. hardware HEVC encode
  -prio_speed 0 -spatial_aq 1 \                # 3. quality-first + adaptive QP
  -g 600 \                                     # 4. long GOP for static content
  -tag:v hvc1 \                                # 5. QuickTime native compatibility
  -c:a aac -b:a 96k \                          # 6. modest audio bitrate
  -movflags +faststart \                       # 7. instant streaming
  output.mov
```

### 1. mpdecimate — Drop duplicate frames

A 120fps screen recording captures 7,200 frames per minute. But the screen rarely changes 120 times per second — most consecutive frames are pixel-identical to the one before. mpdecimate scans 8×8 pixel blocks for differences against configurable thresholds (`hi=768`, `lo=320`, `frac=0.33` by default) and drops frames where nothing meaningful changed.

For a typical screen recording, this alone removes 30–60% of frames *with zero visible difference* — they were duplicates anyway.

`setpts=N/FRAME_RATE/TB` re-times the kept frames so playback speed stays the same. Without this, the video would play 2-3x faster.

### 2. hevc_videotoolbox — Hardware encoding

Apple Silicon has a dedicated chip called the **Media Engine** that handles HEVC encoding/decoding. It's separate from the CPU and runs at extremely low power.

Software encoders like `libx265` analyze each frame for hours of accumulated CPU time, making intelligent decisions that produce slightly smaller files. But they pin the CPU at 100% for minutes, spinning the fans and warming the chassis.

The Media Engine produces files ~10-15% larger than `libx265` at the same quality, but encodes ~10x faster with effectively zero CPU usage. For most use cases, this trade-off is overwhelmingly worth it.

### 3. q:v 60 — Quality target

`hevc_videotoolbox`'s `-q:v` parameter ranges 0-100, where higher values mean better quality + larger files. (This is *opposite* to libx265's CRF, which is a common confusion.)

We tested across the entire range and measured SSIM (Structural Similarity Index) against the source:

| q | SSIM | Compression |
|---|------|-------------|
| 40 | 0.946 | Visible artifacts on close inspection |
| 50 | 0.953 | Subtle differences |
| **60** | **0.992** | **Visually transparent** |
| 70 | 0.997 | Near-source |

SSIM > 0.99 is below the threshold of human visual detection. **q=60 is the sweet spot** for transparent quality.

### 3b. spatial_aq + prio_speed — Smarter encoding

`-spatial_aq 1` enables Adaptive Quantization. The encoder analyzes each frame and allocates more bits to high-frequency areas (text, edges, fine detail) and fewer bits to flat areas (solid backgrounds, gradients). The result is smaller files at the same perceptual quality.

`-prio_speed 0` tells videotoolbox to prioritize quality over encoding speed. Since we're already running at 2-4x realtime, taking a bit more time per frame is fine.

### 4. -g 600 — Long GOP for static content

A GOP (Group of Pictures) is the cluster of frames between two keyframes. Keyframes are large (full frame) while P-frames between them are small (only deltas).

For dynamic content (sports, action), short GOPs (every ~250 frames) help with seek performance and error resilience. For *static* content like screen recordings, short GOPs waste bits on redundant keyframes.

Setting `-g 600` (a keyframe every 600 frames at most) saves 50–70% on file size for typical screen recordings. We tested up to `-g 99999` and found diminishing returns past 600.

The trade-off: seeking is slightly slower (the player must scan back to find the previous keyframe). For files watched start-to-finish or shared via download, this is invisible.

### 5. -tag:v hvc1 — QuickTime compatibility

By default, `hevc_videotoolbox` writes `hev1` codec tags. QuickTime, iOS, and most Apple software *don't recognize* `hev1` and refuse to play the file. The `hvc1` tag is bit-identical content but the right four-letter signature.

Without this, your files play in VLC but not in QuickTime. Almost every Mac HEVC tool gets this wrong.

### 6. AAC 96k audio

Screen recordings have system audio (notification sounds) and voice-over. 96 kbps AAC is more than enough — voice is intelligible at 64 kbps, music starts to sound thin below 128 kbps.

Reducing audio bitrate matters less than you'd think — at 96 kbps audio for 3 minutes is only ~2 MB. The video is where the savings live.

### 7. +faststart — Streaming-friendly metadata

By default, MP4/MOV files have their metadata (`moov` atom) at the end. To start playback, players must read to the end first. With `+faststart`, the metadata is moved to the beginning — the file plays immediately when streamed or previewed.

## What we considered and rejected

### Two-pass encoding

`hevc_videotoolbox` doesn't actually use the first-pass analysis. Apple's encoder is designed for real-time streaming, not the multi-pass quality optimization that software encoders do. Two-pass with videotoolbox just doubles the encoding time for zero quality benefit. Verified empirically.

### 10-bit (main10) profile

Theoretically, 10-bit HEVC compresses better for content with subtle gradients. In practice, screen recordings use solid colors and sharp edges where 10-bit doesn't help — and for screen content, our tests showed 10-bit produces *bigger* files.

### libx265 with `--tune ssim`

Software encoders compress 10-15% better than hardware. But they require minutes of full CPU time per minute of video. For our use case (compress and forget), the time cost outweighs the size benefit.

### AV1 (SVT-AV1)

AV1 is a newer codec that compresses ~25% better than HEVC. But:
- Apple Silicon has no hardware AV1 *encoder* (decoder yes, encoder no — through M4)
- Software AV1 encoding is loud and slow
- AV1 compatibility on older devices requires software decode, which can heat up the *viewer's* device

When Apple adds hardware AV1 encoding (likely M5), quietshrink will switch to it.

### Variable bitrate target

Targeting a specific bitrate (e.g., `-b:v 1500k`) gives more predictable file sizes. But it can cause visible quality drops in complex frames. Quality-based encoding (q-level) lets the encoder spend bits where they're needed and stay constrained where they're not.

### Denoise pre-filter (hqdn3d)

Theoretically, light denoising can improve compression efficiency. For screen recordings (no noise to denoise), it's pure overhead — verified empirically: zero size benefit, 2x slower encoding.

## Why this combination is Pareto-optimal

There's a classic trade-off in video compression:

- **Software encoders**: smallest files, slowest, loud
- **Hardware encoders**: bigger files, fast, silent
- **Smart filters** (mpdecimate, GOP tuning): orthogonal — work on top of either

By using **hardware encoding** + **smart filtering**, we get most of the size benefits of software encoders (mpdecimate + long GOP make up for the encoder's lower efficiency) while keeping all the speed and silence of hardware.

The user gets:
- Files about as small as software encoders
- ~10x faster encoding
- Silent computer
- No paid software

This is the Pareto front for screen recording compression on Apple Silicon in 2026.
