# Animated Artwork Assets

Place bundled animated artwork loops in this directory as `.mov` files (HEVC/H.265) with matching preview `.jpg` images. The code references the following sample assets:

- `RainLoop.mov` + `RainLoop.jpg`
- `CampfireLoop.mov` + `CampfireLoop.jpg`

Each video should be a short, seamless loop (3–7 seconds), encoded as H.264 or HEVC without audio. Previews should be generated from the first frame of the loop to avoid visual pops when playback starts.

Use `scripts/prepare_loop.sh` to crop, scale, and transcode source footage with ffmpeg. It automatically writes outputs into `Blankie/Assets/AnimatedArtwork` using the source filename (minus extension):

```bash
scripts/prepare_loop.sh path/to/Rain.mp4
```

The script outputs `RainLoop.mov` (HEVC with `hvc1` tag) and `RainLoop.jpg` (first frame). Both files should live in source control.

Flags remain available if you need to override defaults (e.g., `--output-dir`, `--name`, `--size`, `--codec`, `--crf`).
