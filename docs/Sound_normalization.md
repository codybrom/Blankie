# Sound Normalization in Blankie

## Overview

Blankie implements EBU R 128 loudness normalization to ensure consistent playback volumes across all ambient sounds. This document describes the normalization system and how to use it effectively.

## Key Features

### 1. EBU R 128 Loudness Analysis

Blankie performs comprehensive audio analysis using the ITU-R BS.1770-4 standard:

- **Integrated Loudness (LUFS)**: Measures the overall perceived loudness of the entire sound file
- **True Peak (dBTP)**: Detects the maximum peak level including inter-sample peaks using 4x oversampling
- **Two-stage Gating**: Applies absolute gating at -70 LUFS and relative gating at -10 LU for accurate measurements
- **Target Level**: -27 LUFS (optimized for ambient sound playback)

### 2. Playback Profiles

Analysis results are cached in playback profiles for efficient runtime performance:

```swift
struct PlaybackProfile {
  let integratedLUFS: Float    // Measured loudness
  let truePeakdBTP: Float      // Maximum true peak level
  let gainDB: Float            // Pre-calculated gain to apply
  let needsLimiter: Bool       // Whether soft limiting is needed
}
```

Profiles are stored in:

- **macOS**: `~/Library/Application Support/Blankie/playbackProfiles.json`
- **iOS**: `<App Container>/Library/Application Support/Blankie/playbackProfiles.json`

### 3. Automatic Gain & Limiting

- **Gain Calculation**: Automatically calculates the gain needed to reach -27 LUFS
- **True Peak Protection**: Prevents clipping by checking if gain would push true peak above -1 dBTP
- **Soft Limiting**: Applies tanh-based soft clipping when needed to prevent distortion

### 4. User Interface

The sound customization sheet displays:

- Integrated loudness in LUFS
- True peak in dBTP
- Applied gain in dB
- 🔒 icon when limiting is active

Example: `(-18.3 LUFS, TP: -0.5 dBTP 🔒, Gain: +8.7 dB)`

## Development Tools

### Batch Analysis

Analyze all sounds and update their profiles:

```swift
// In the debugger or a development UI
Task {
  let count = await AudioManager.shared.analyzeAllSounds()
  print("Analyzed \(count) sounds")
}
```

### Force Re-analysis

To re-analyze all sounds (useful after algorithm updates):

```swift
Task {
  let count = await AudioManager.shared.analyzeAllSounds(forceReanalysis: true)
  print("Re-analyzed \(count) sounds")
}
```

### Check Missing Profiles

Find sounds that haven't been analyzed:

```swift
let needsAnalysis = AudioManager.shared.soundsNeedingAnalysis()
print("Sounds needing analysis: \(needsAnalysis.map { $0.fileName })")
```

## Implementation Details

### Audio Analysis Pipeline

1. **Decode audio** to PCM format at native sample rate
2. **Apply K-weighting filters** (pre-filter + RLB filter) as per ITU-R BS.1770-4
3. **Calculate per-channel power** with proper channel weighting
4. **Apply two-stage gating** to exclude silence and quiet passages
5. **Compute integrated loudness** from gated measurements
6. **Detect true peak** using 4x oversampling and linear interpolation
7. **Calculate gain and limiter requirements**
8. **Store results** in PlaybackProfile for runtime use

### Runtime Normalization

During playback:

1. Load cached PlaybackProfile for the sound
2. Apply pre-calculated gain during volume updates
3. Apply soft limiting if profile indicates needsLimiter
4. Update player volume with normalized value

### Soft Limiter Algorithm

When `needsLimiter` is true and effective volume > 0.95:

```swift
let softLimitThreshold: Float = 0.85
if effectiveVolume > softLimitThreshold {
  let excess = (effectiveVolume - softLimitThreshold) / (1.0 - softLimitThreshold)
  let limited = softLimitThreshold + (1.0 - softLimitThreshold) * tanh(excess * 2)
  effectiveVolume = limited
}
```

## Best Practices

1. **Initial Setup**: Run batch analysis on first launch or when adding new sounds
2. **Content Updates**: Re-analyze sounds after significant app updates
3. **Custom Sounds**: Analysis runs automatically when users add custom sounds
4. **Monitoring**: Check for sounds with `needsLimiter = true` as they may benefit from pre-processing

## Analysis Timing

Blankie performs audio analysis **at runtime**, not during build:

- **Built-in sounds**: Analyzed on first use or when profiles are missing
- **Custom sounds**: Analyzed when added or when opening the sound editor
- **On-demand**: Via the batch analysis function for all sounds

## Future Enhancements

- Loudness Range (LRA) analysis for dynamic content
- Real-time loudness metering during playback
- User-adjustable target LUFS levels
- Batch pre-processing tools for content creators
