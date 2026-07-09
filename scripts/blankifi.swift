#!/bin/sh
set -e
SELF="$0"
ROOT=$(cd "$(dirname "$SELF")/.." && pwd)
BUILD="$ROOT/scripts/.build"
BIN="$BUILD/blankifi"
SRC="$BUILD/blankifi-main.swift"
ANALYZERS="$ROOT/Blankie/Utils/AudioAnalyzer.swift $ROOT/Blankie/Utils/AudioAnalyzer+Weighting.swift $ROOT/Blankie/Utils/AudioAnalyzer+LUFS.swift $ROOT/Blankie/Utils/Logging.swift"
stale=0
[ -x "$BIN" ] || stale=1
for f in "$SELF" $ANALYZERS; do [ "$f" -nt "$BIN" ] && stale=1; done
if [ "$stale" -eq 1 ]; then
  echo "blankifi: compiling..." 1>&2
  mkdir -p "$BUILD"
  awk '/^\/\/<<<BLANKIFI-SWIFT>>>/{found=1;next} found' "$SELF" > "$SRC"
  xcrun -sdk macosx swiftc -O -target "$(uname -m)-apple-macosx14.0" "$SRC" $ANALYZERS -o "$BIN" 1>&2
fi
exec "$BIN" "$@"
//<<<BLANKIFI-SWIFT>>>

//  blankifi.swift — Blankie's audio toolkit
//
//  Usage:  ./scripts/blankifi.swift <subcommand> [args]
//
//    analyze    <file>                                          LUFS / peak / true-peak / duration
//    loop       <file> [out-prefix]                             loop-seam metrics + PNG plots
//    fix        <in> <out> [--xfade-ms 250] [--bitrate 192000]  seamless-loop repair
//    convert    <in> <out.m4a> [--bitrate 192000]               transcode to 44.1k stereo M4A
//    reanalyze  [--write] [--json PATH] [--sounds-dir DIR]      batch re-measure sounds.json
//
//  The shell preamble above compiles this file together with the app's real
//  AudioAnalyzer, so `analyze`/`reanalyze` report the exact LUFS as the app

import AVFoundation
import Accelerate
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Audio I/O

/// Decode an entire audio file into per-channel float samples at the file's
/// native sample rate. Reads the whole file into memory.
func readChannels(_ url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
  let file = try AVAudioFile(forReading: url)
  let format = file.processingFormat
  guard
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
  else { throw NSError(domain: "blankifi", code: 1) }
  try file.read(into: buffer)
  let n = Int(buffer.frameLength)
  var channels = [[Float]]()
  for c in 0..<Int(format.channelCount) {
    channels.append(Array(UnsafeBufferPointer(start: buffer.floatChannelData![c], count: n)))
  }
  return (channels, format.sampleRate)
}

/// Encode per-channel float samples to an AAC `.m4a`, overwriting any existing
/// file. `bitRate` is in bits per second; `sampleRate` must match `channels`.
func writeM4A(_ channels: [[Float]], sampleRate: Double, bitRate: Int, to url: URL) throws {
  let ch = channels.count
  let n = channels[0].count
  try? FileManager.default.removeItem(at: url)
  let settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: ch,
    AVEncoderBitRateKey: bitRate,
  ]
  let outFile = try AVAudioFile(forWriting: url, settings: settings)
  let pf = outFile.processingFormat
  guard let buffer = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: AVAudioFrameCount(n)) else {
    throw NSError(domain: "blankifi", code: 2)
  }
  buffer.frameLength = AVAudioFrameCount(n)
  for c in 0..<ch {
    channels[c].withUnsafeBufferPointer { src in
      buffer.floatChannelData![c].update(from: src.baseAddress!, count: n)
    }
  }
  try outFile.write(from: buffer)
}

// MARK: - DSP

/// Down-mix to mono by averaging channels. Assumes every channel has the
/// length of channel 0.
func toMono(_ channels: [[Float]]) -> [Float] {
  let n = channels[0].count
  if channels.count == 1 { return channels[0] }
  var m = [Float](repeating: 0, count: n)
  for c in channels { vDSP_vadd(m, 1, c, 1, &m, 1, vDSP_Length(n)) }
  var scale = 1.0 / Float(channels.count)
  vDSP_vsmul(m, 1, &scale, &m, 1, vDSP_Length(n))
  return m
}

/// Short-time RMS envelope: the linear RMS of each non-overlapping window.
/// `win` is a length in SAMPLES (e.g. `Int(sr * 0.002)` for 2 ms). The trailing
/// partial window is included.
func rmsEnvelope(_ sig: ArraySlice<Float>, win: Int) -> [Float] {
  let a = Array(sig)
  var out = [Float]()
  a.withUnsafeBufferPointer { p in
    var i = 0
    while i < a.count {
      let len = min(win, a.count - i)
      var ms: Float = 0
      vDSP_measqv(p.baseAddress! + i, 1, &ms, vDSP_Length(len))
      out.append((ms + 1e-12).squareRoot())
      i += win
    }
  }
  return out
}

/// RMS level of a segment, in dBFS.
func dbRMS(_ seg: ArraySlice<Float>) -> Float {
  let a = Array(seg)
  var ms: Float = 0
  vDSP_measqv(a, 1, &ms, vDSP_Length(a.count))
  return 20 * log10(ms.squareRoot() + 1e-9)
}

/// Peak absolute sample value of a segment, linear 0...1 (not dB).
func peakMag(_ seg: ArraySlice<Float>) -> Float {
  let a = Array(seg)
  var m: Float = 0
  vDSP_maxmgv(a, 1, &m, vDSP_Length(a.count))
  return m
}

func median(_ a: [Float]) -> Float {
  let s = a.sorted()
  let n = s.count
  return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

/// Detect where the leading/trailing silence + isolated edge transient end, so a
/// loop can be cut to steady ambient. Returns sample indices [headCut, tailCut).
func detectEdges(_ mono: [Float], sr: Double) -> (head: Int, tail: Int) {
  let n = mono.count
  let win = Int(sr * 0.002)  // 2 ms analysis windows
  let env = rmsEnvelope(mono[0...], win: win)
  let bed = median(env)  // steady ambient floor; median ignores the transients
  let thr = bed * 3  // 3x bed = clearly a transient, not ambient
  let settle = bed * 1.5  // back under 1.5x bed = returned to ambient
  let need = Int(0.015 / 0.002)  // ...sustained 15 ms before we call it settled
  let above = env.indices.filter { env[$0] > thr }
  guard let first = above.first, let last = above.last else { return (0, n) }
  var run = 0
  var headWin = first + 1
  for i in (first + 1)..<env.count {
    run = env[i] < settle ? run + 1 : 0
    if run >= need {
      headWin = i - run + 1
      break
    }
  }
  run = 0
  var tailWin = last
  var i = last - 1
  while i >= 0 {
    run = env[i] < settle ? run + 1 : 0
    if run >= need {
      tailWin = i + run
      break
    }
    i -= 1
  }
  var headCut = min(headWin * win, n - 1)
  var tailCut = min(tailWin * win, n)
  func snapZC(_ start: Int, _ lo: Int, _ hi: Int) -> Int {
    var j = max(lo, start)
    while j < min(hi, n - 1) {
      if mono[j] <= 0 && mono[j + 1] >= 0 { return j }
      j += 1
    }
    return start
  }
  headCut = snapZC(headCut, 0, headCut + win)
  tailCut = snapZC(max(0, tailCut - win), tailCut - win, tailCut)
  return (headCut, tailCut)
}

// MARK: - Plotting (CoreGraphics)

struct Series {
  let x: [Double]
  let y: [Double]
  let rgb: (CGFloat, CGFloat, CGFloat)
}
struct Band {
  let title: String
  let series: Series
  let yMin: Double
  let yMax: Double
  let xLabel: String
}

func drawText(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 12) {
  let attrs: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
      "Helvetica" as CFString, size, nil),
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
      red: 0.15, green: 0.15, blue: 0.15, alpha: 1),
  ]
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
  ctx.textPosition = CGPoint(x: x, y: y)
  CTLineDraw(line, ctx)
}

func renderBands(_ bands: [Band], width: Int, height: Int, to url: URL) {
  guard
    let ctx = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return }
  ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let bandH = CGFloat(height) / CGFloat(bands.count)
  let left: CGFloat = 64
  let right: CGFloat = 16
  let top: CGFloat = 26
  let bottom: CGFloat = 30
  for (bi, band) in bands.enumerated() {
    let bandBottom = CGFloat(height) - CGFloat(bi + 1) * bandH
    let plot = CGRect(
      x: left, y: bandBottom + bottom, width: CGFloat(width) - left - right,
      height: bandH - top - bottom)
    let xs = band.series.x
    let ys = band.series.y
    let xMin = xs.first ?? 0
    let xMax = xs.last ?? 1
    func mapX(_ v: Double) -> CGFloat {
      plot.minX + CGFloat((v - xMin) / (xMax - xMin)) * plot.width
    }
    func mapY(_ v: Double) -> CGFloat {
      plot.minY + CGFloat((v - band.yMin) / (band.yMax - band.yMin)) * plot.height
    }
    ctx.setStrokeColor(CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1))
    ctx.setLineWidth(0.5)
    var gridYs = [band.yMin, (band.yMin + band.yMax) / 2, band.yMax]
    if band.yMin < 0 && band.yMax > 0 { gridYs.append(0) }
    for gy in gridYs {
      ctx.beginPath()
      ctx.move(to: CGPoint(x: plot.minX, y: mapY(gy)))
      ctx.addLine(to: CGPoint(x: plot.maxX, y: mapY(gy)))
      ctx.strokePath()
      drawText(ctx, String(format: "%g", gy), 6, mapY(gy) - 4, size: 10)
    }
    ctx.setStrokeColor(CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1))
    ctx.stroke(plot)
    ctx.setStrokeColor(
      CGColor(red: band.series.rgb.0, green: band.series.rgb.1, blue: band.series.rgb.2, alpha: 1))
    ctx.setLineWidth(0.7)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: mapX(xs[0]), y: mapY(ys[0])))
    for i in 1..<xs.count { ctx.addLine(to: CGPoint(x: mapX(xs[i]), y: mapY(ys[i]))) }
    ctx.strokePath()
    drawText(ctx, band.title, plot.minX, plot.maxY + 8, size: 13)
    drawText(ctx, String(format: "%g", xMin), plot.minX, plot.minY - 18, size: 10)
    drawText(ctx, String(format: "%g", xMax), plot.maxX - 30, plot.minY - 18, size: 10)
    drawText(ctx, band.xLabel, (plot.minX + plot.maxX) / 2 - 30, plot.minY - 18, size: 10)
  }
  guard let image = ctx.makeImage(),
    let dest = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { return }
  CGImageDestinationAddImage(dest, image, nil)
  CGImageDestinationFinalize(dest)
}

// MARK: - Subcommands

func cmdAnalyze(_ args: [String]) async {
  guard let path = args.first else { fail("analyze <file>") }
  let url = URL(fileURLWithPath: path)
  // comprehensiveAnalysis swallows read errors and returns defaults, so verify
  // the file actually decodes first — otherwise we'd print bogus values.
  guard (try? AVAudioFile(forReading: url)) != nil else { fail("cannot read \(path)") }
  let r = await AudioAnalyzer.comprehensiveAnalysis(at: url)
  print("file=\(url.lastPathComponent)")
  if let d = r.duration { print(String(format: "duration: %.6f", d)) }
  if let l = r.lufs { print("lufs: \(l)") }
  print("normalizationFactor: \(r.normalizationFactor)")
  print(String(format: "gain: %+.2f dB", 20 * log10(r.normalizationFactor)))
  if let p = r.peakdBFS { print(String(format: "peak: %.2f dBFS", p)) }
  if let tp = r.truePeakdBTP { print(String(format: "truePeak: %.2f dBTP", tp)) }
  print("needsLimiter: \(r.needsLimiter)")
}

func cmdLoop(_ args: [String]) {
  guard let path = args.first else { fail("loop <file> [out-prefix]") }
  let prefix = args.count > 1 ? args[1] : "loop"
  guard let (channels, sr) = try? readChannels(URL(fileURLWithPath: path)) else {
    fail("read failed")
  }
  let mono = toMono(channels)
  let n = mono.count
  let dur = Double(n) / sr
  let ms30 = Int(sr * 0.03)
  let sec = Int(sr * 1.0)
  print("file=\(path)")
  print(String(format: "duration=%.4fs  sr=%.0f", dur, sr))
  print(String(format: "wrap sample-jump |first-last| = %.5f", abs(mono.first! - mono.last!)))
  print(
    String(
      format: "RMS  head30ms=%.1fdB  tail30ms=%.1fdB  whole=%.1fdB",
      dbRMS(mono[0..<ms30]), dbRMS(mono[(n - ms30)..<n]), dbRMS(mono[0..<n])))
  print(
    String(
      format: "peak |x|  first1s=%.3f  last1s=%.3f  middle=%.3f",
      peakMag(mono[0..<sec]), peakMag(mono[(n - sec)..<n]), peakMag(mono[sec..<(n - sec)])))
  let win = Int(sr * 0.002)
  let env = rmsEnvelope(mono[0...], win: win)
  let bed = median(env)
  let above = env.indices.filter { env[$0] > bed * 3 }
  if let f = above.first, let l = above.last {
    print(
      String(
        format:
          "edge transients: bed=%.1fdB  first @ %.0fms (%.1fdB)  last @ %.0fms before end (%.1fdB)",
        20 * log10(bed + 1e-9), Double(f * win) / sr * 1000, 20 * log10(env[f] + 1e-9),
        Double(n - l * win) / sr * 1000, 20 * log10(env[l] + 1e-9)))
  }
  func envSeries(
    _ s: ArraySlice<Float>, _ winMs: Double, _ xOff: Double, _ rgb: (CGFloat, CGFloat, CGFloat)
  ) -> Series {
    let w = Int(sr * winMs / 1000)
    let e = rmsEnvelope(s, win: w)
    return Series(
      x: (0..<e.count).map { xOff + Double($0) * Double(w) / sr },
      y: e.map { Double(20 * log10($0 + 1e-9)) }, rgb: rgb)
  }
  let hw = Int(sr * 1.5)
  renderBands(
    [
      Band(
        title: String(format: "Full RMS envelope (20ms)  dur=%.3fs", dur),
        series: envSeries(mono[0...], 20, 0, (0.12, 0.47, 0.71)), yMin: -60, yMax: 0,
        xLabel: "seconds"),
      Band(
        title: "HEAD first 1.5s (2ms RMS)",
        series: envSeries(mono[0..<min(hw, n)], 2, 0, (1.0, 0.5, 0.05)), yMin: -60, yMax: 0,
        xLabel: "seconds"),
      Band(
        title: "TAIL last 1.5s (2ms RMS)",
        series: envSeries(mono[max(0, n - hw)..<n], 2, dur - 1.5, (0.17, 0.63, 0.17)), yMin: -60,
        yMax: 0, xLabel: "seconds"),
    ], width: 1260, height: 810, to: URL(fileURLWithPath: "\(prefix)-envelope.png"))
  let ms120 = Int(sr * 0.12)
  var seam = Array(mono[(n - ms120)..<n])
  seam.append(contentsOf: mono[0..<ms120])
  renderBands(
    [
      Band(
        title: "SEAM: tail -> head  (0 = loop wrap point)",
        series: Series(
          x: (0..<seam.count).map { Double($0) / sr * 1000 - Double(ms120) / sr * 1000 },
          y: seam.map { Double($0) }, rgb: (0.84, 0.15, 0.16)), yMin: -0.15, yMax: 0.15,
        xLabel: "ms relative to wrap")
    ], width: 1260, height: 360, to: URL(fileURLWithPath: "\(prefix)-seam.png"))
  print("wrote \(prefix)-envelope.png and \(prefix)-seam.png")
}

func cmdFix(_ args: [String]) {
  var rest = args
  var xfadeMs = 250.0
  var bitRate = 192_000
  if let i = rest.firstIndex(of: "--xfade-ms") {
    xfadeMs = Double(rest[i + 1])!
    rest.removeSubrange(i...(i + 1))
  }
  if let i = rest.firstIndex(of: "--bitrate") {
    bitRate = Int(rest[i + 1])!
    rest.removeSubrange(i...(i + 1))
  }
  guard rest.count >= 2 else { fail("fix <in> <out> [--xfade-ms 250] [--bitrate 192000]") }
  guard let (channels, sr) = try? readChannels(URL(fileURLWithPath: rest[0])) else {
    fail("read failed")
  }
  let n = channels[0].count
  let mono = toMono(channels)
  let (headCut, tailCut) = detectEdges(mono, sr: sr)
  let bodyN = tailCut - headCut
  let xf = Int(sr * xfadeMs / 1000)
  guard xf * 2 < bodyN else { fail("crossfade too long for body") }
  let outN = bodyN - xf
  var fadeIn = [Float](repeating: 0, count: xf)
  var fadeOut = [Float](repeating: 0, count: xf)
  for i in 0..<xf {
    let t = Double(i) / Double(xf - 1) * (.pi / 2)
    fadeIn[i] = Float(sin(t))
    fadeOut[i] = Float(cos(t))
  }
  var outChannels = [[Float]]()
  for c in 0..<channels.count {
    let body = Array(channels[c][headCut..<tailCut])
    var outc = [Float](repeating: 0, count: outN)
    for i in 0..<xf { outc[i] = body[i] * fadeIn[i] + body[bodyN - xf + i] * fadeOut[i] }
    for k in 0..<(outN - xf) { outc[xf + k] = body[xf + k] }
    outChannels.append(outc)
  }
  do {
    try writeM4A(outChannels, sampleRate: sr, bitRate: bitRate, to: URL(fileURLWithPath: rest[1]))
  } catch {
    fail("write failed: \(error)")
  }
  let outMono = toMono(outChannels)
  print(
    String(
      format: "trimmed head %.0fms, tail %.0fms", Double(headCut) / sr * 1000,
      Double(n - tailCut) / sr * 1000))
  print(
    String(
      format: "in dur=%.4fs -> out dur=%.4fs  xfade=%.0fms", Double(n) / sr, Double(outN) / sr,
      xfadeMs))
  print(String(format: "new wrap sample-jump=%.5f", abs(outMono.first! - outMono.last!)))
  print("wrote \(rest[1])")
}

func cmdConvert(_ args: [String]) {
  var rest = args
  var bitRate = 192_000
  if let i = rest.firstIndex(of: "--bitrate") {
    bitRate = Int(rest[i + 1])!
    rest.removeSubrange(i...(i + 1))
  }
  guard rest.count >= 2 else { fail("convert <in> <out.m4a> [--bitrate 192000]") }
  let inURL = URL(fileURLWithPath: rest[0])
  let outURL = URL(fileURLWithPath: rest[1])
  do {
    let inFile = try AVAudioFile(forReading: inURL)
    let inFormat = inFile.processingFormat
    guard
      let inBuf = AVAudioPCMBuffer(
        pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(inFile.length))
    else { fail("buffer alloc failed") }
    try inFile.read(into: inBuf)
    guard
      let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)
    else { fail("target format failed") }
    let outBuf: AVAudioPCMBuffer
    if inFormat.sampleRate == 44100 && inFormat.channelCount == 2 {
      outBuf = inBuf
    } else {
      let cap = AVAudioFrameCount(Double(inFile.length) * 44100 / inFormat.sampleRate) + 8192
      guard let conv = AVAudioConverter(from: inFormat, to: target),
        let ob = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap)
      else { fail("converter init failed") }
      var fed = false
      var convErr: NSError?
      conv.convert(to: ob, error: &convErr) { _, status in
        if fed {
          status.pointee = .endOfStream
          return nil
        }
        fed = true
        status.pointee = .haveData
        return inBuf
      }
      if let e = convErr { fail("convert failed: \(e)") }
      outBuf = ob
    }
    var channels = [[Float]]()
    let n = Int(outBuf.frameLength)
    for c in 0..<Int(outBuf.format.channelCount) {
      channels.append(Array(UnsafeBufferPointer(start: outBuf.floatChannelData![c], count: n)))
    }
    try writeM4A(channels, sampleRate: outBuf.format.sampleRate, bitRate: bitRate, to: outURL)
    print(
      String(
        format: "converted -> %@  (%.3fs, %.0fk AAC 44.1k stereo)", outURL.lastPathComponent,
        Double(n) / 44100.0, Double(bitRate) / 1000.0))
  } catch {
    // convert reads whatever CoreAudio/AVAudioFile supports on this macOS
    // (wav/aiff/mp3/m4a/caf/flac/ogg here); anything it can't decode lands here.
    fail("convert failed (unreadable or unsupported input): \(error)")
  }
}

func cmdReanalyze(_ args: [String]) async {
  var jsonPath = "Blankie/Resources/sounds.json"
  var soundsDir = "Blankie/Resources/Sounds"
  var write = false
  var rest = args
  if let i = rest.firstIndex(of: "--json") {
    jsonPath = rest[i + 1]
    rest.removeSubrange(i...(i + 1))
  }
  if let i = rest.firstIndex(of: "--sounds-dir") {
    soundsDir = rest[i + 1]
    rest.removeSubrange(i...(i + 1))
  }
  if let i = rest.firstIndex(of: "--write") {
    write = true
    rest.remove(at: i)
  }

  guard var text = try? String(contentsOfFile: jsonPath, encoding: .utf8),
    let data = text.data(using: .utf8),
    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let sounds = obj["sounds"] as? [[String: Any]]
  else { fail("could not read/parse \(jsonPath)") }

  print(
    "Re-analyzing \(sounds.count) sounds with the app's K-weighted AudioAnalyzer (target -27 LUFS)")
  print(
    padR("sound", 16) + padL("oldLUFS", 9) + padL("newLUFS", 9) + padL("ΔLUFS", 8)
      + padL("oldFac", 9) + padL("newFac", 9) + padL("truePk", 9) + padL("predPeak", 10) + "  flags")
  var changed = 0
  for s in sounds {
    guard let fileName = s["fileName"] as? String else { continue }
    let fileURL = ["m4a", "wav", "mp3", "aiff"].lazy
      .map { URL(fileURLWithPath: "\(soundsDir)/\(fileName).\($0)") }
      .first { FileManager.default.fileExists(atPath: $0.path) }
    guard let url = fileURL else {
      print("\(fileName): file not found")
      continue
    }
    let r = await AudioAnalyzer.comprehensiveAnalysis(at: url)
    guard let newLufs = r.lufs else {
      print("\(fileName): analysis failed")
      continue
    }
    let oldLufs = (s["lufs"] as? NSNumber)?.floatValue ?? 0
    let oldFac = (s["normalizationFactor"] as? NSNumber)?.floatValue ?? 0
    let newFac = r.normalizationFactor
    let truePeak = r.truePeakdBTP ?? -.infinity
    let needsLimiter = r.needsLimiter
    let predPeak = truePeak + 20 * log10(newFac)
    var flags = needsLimiter ? "limiter " : ""
    if abs(newLufs - oldLufs) > 0.5 { flags += "Δ>0.5 " }
    print(
      padR(fileName, 16) + padL(String(format: "%.3f", oldLufs), 9)
        + padL(String(format: "%.3f", newLufs), 9)
        + padL(String(format: "%+.2f", newLufs - oldLufs), 8)
        + padL(String(format: "%.4f", oldFac), 9) + padL(String(format: "%.4f", newFac), 9)
        + padL(String(format: "%.2f", truePeak), 9) + padL(String(format: "%.2f", predPeak), 10)
        + "  " + flags)
    if write {
      text = upsertField(text, fileName: fileName, key: "lufs", value: "\(newLufs)", before: nil)
      text = upsertField(
        text, fileName: fileName, key: "needsLimiter", value: needsLimiter ? "true" : "false",
        before: "normalizationFactor")
      text = upsertField(
        text, fileName: fileName, key: "normalizationFactor", value: "\(newFac)", before: nil)
      if truePeak.isFinite {
        text = upsertField(
          text, fileName: fileName, key: "truePeakdBTP", value: "\(truePeak)", before: nil)
      }
      changed += 1
    }
  }
  if write {
    do { try text.write(toFile: jsonPath, atomically: true, encoding: .utf8) } catch {
      fail("write failed: \(error)")
    }
    print("\n✅ wrote \(changed) updated entries to \(jsonPath)")
  } else {
    print("\n(report only — pass --write to update \(jsonPath))")
  }
}

/// Set `key` to `value` inside the JSON object that contains
/// `"fileName": "<fileName>"`, preserving all other text and formatting. If the
/// key exists its value is replaced; otherwise a new line is inserted before
/// `beforeKey` (to keep sorted order), or appended as the last field if
/// `beforeKey` is nil. `value` is the raw JSON token (number / true / false).
func upsertField(_ text: String, fileName: String, key: String, value: String, before beforeKey: String?)
  -> String
{
  guard let anchor = text.range(of: "\"fileName\": \"\(fileName)\"") else { return text }
  guard
    let objStart = text.range(
      of: "{", options: .backwards, range: text.startIndex..<anchor.lowerBound),
    let objEnd = text.range(of: "}", range: anchor.upperBound..<text.endIndex)
  else { return text }
  let objRange = objStart.lowerBound..<objEnd.upperBound
  var obj = String(text[objRange])

  // Replace if the key already exists (value runs to end of its line).
  if let re = try? NSRegularExpression(pattern: "(\"\(key)\"\\s*:\\s*)[^,\\n]+"),
    re.firstMatch(in: obj, range: NSRange(obj.startIndex..., in: obj)) != nil
  {
    let ns = obj as NSString
    obj = re.stringByReplacingMatches(
      in: obj, range: NSRange(location: 0, length: ns.length), withTemplate: "$1\(value)")
    return text.replacingCharacters(in: objRange, with: obj)
  }

  if let beforeKey = beforeKey, let kr = obj.range(of: "\"\(beforeKey)\"") {
    // Insert a new field line before beforeKey's line, matching its indentation.
    let nl = obj[obj.startIndex..<kr.lowerBound].lastIndex(of: "\n") ?? obj.startIndex
    let lineStart = obj.index(after: nl)
    let indent = String(obj[lineStart..<kr.lowerBound])
    obj.insert(contentsOf: "\(indent)\"\(key)\": \(value),\n", at: lineStart)
  } else {
    // Append as the last field: add a comma to the current last field, then a new line.
    guard let brace = obj.range(of: "}", options: .backwards) else { return text }
    let beforeBrace = obj[obj.startIndex..<brace.lowerBound]
    guard let braceNl = beforeBrace.lastIndex(of: "\n") else { return text }
    let lastFieldStart =
      obj.index(after: beforeBrace[beforeBrace.startIndex..<braceNl].lastIndex(of: "\n") ?? braceNl)
    let indent = String(obj[lastFieldStart..<(obj[lastFieldStart...].firstIndex(of: "\"") ?? lastFieldStart)])
    obj.insert(contentsOf: ",\n\(indent)\"\(key)\": \(value)", at: braceNl)
  }
  return text.replacingCharacters(in: objRange, with: obj)
}

// MARK: - Entry

func fail(_ message: String) -> Never {
  FileHandle.standardError.write("blankifi: \(message)\n".data(using: .utf8)!)
  exit(1)
}

func padR(_ s: String, _ w: Int) -> String {
  s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
}
func padL(_ s: String, _ w: Int) -> String {
  s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
}

// MARK: - Haptics (audio → AHAP)

/// Zero-crossing rate of a segment (0…~1). A cheap brightness cue that needs no
/// FFT: low for a deep hum, high for bright/noisy content.
func zcr(_ seg: ArraySlice<Float>) -> Float {
  let a = Array(seg)
  guard a.count > 1 else { return 0 }
  var c = 0
  for i in 1..<a.count where (a[i] >= 0) != (a[i - 1] >= 0) { c += 1 }
  return Float(c) / Float(a.count - 1)
}

/// Brightness → Core Haptics sharpness, from ZCR. The sqrt expands the low end
/// so mid-frequency pops (a fire crackle over a low rumble) don't read as flat
/// the way a raw high-pass/RMS ratio did.
func sharpnessOf(_ seg: ArraySlice<Float>) -> Float {
  max(0, min(1, zcr(seg).squareRoot() * 1.3))
}

func downsampled(_ v: [Float], _ n: Int) -> [Float] {
  guard v.count > n, n > 0 else { return v }
  return (0..<n).map { v[min(v.count - 1, Int(Double($0) / Double(n) * Double(v.count)))] }
}

func sparkline(_ v: [Float]) -> String {
  let blocks = Array(" ▁▂▃▄▅▆▇█")
  let mx = (v.max() ?? 1) + 1e-9
  return String(v.map { blocks[max(0, min(8, Int(($0 / mx) * 8)))] })
}

func ahapTransient(_ time: Double, _ intensity: Float, _ sharpness: Float) -> [String: Any] {
  [
    "Event": [
      "Time": time, "EventType": "HapticTransient",
      "EventParameters": [
        ["ParameterID": "HapticIntensity", "ParameterValue": Double(intensity)],
        ["ParameterID": "HapticSharpness", "ParameterValue": Double(sharpness)],
      ],
    ]
  ]
}

func ahapContinuous(_ duration: Double, _ sharpness: Float) -> [String: Any] {
  [
    "Event": [
      "Time": 0.0, "EventType": "HapticContinuous", "EventDuration": duration,
      "EventParameters": [
        ["ParameterID": "HapticIntensity", "ParameterValue": 1.0],
        ["ParameterID": "HapticSharpness", "ParameterValue": Double(sharpness)],
      ],
    ]
  ]
}

struct HapticSuggestion {
  let name: String
  let dur: Double
  let startSec: Double
  let envN: [Float]
  let onsets: [(t: Double, i: Float, s: Float)]
  let picks: [(t: Double, i: Float, s: Float)]
  let density: Double
  let sharpness: Float
  let gapFrac: Float
  let transientLike: Bool
  let pattern: [[String: Any]]
}

/// Analyze a sound's audio and derive a ~1s haptic "voice" — either a set of
/// transient taps (percussive, spiky, or bright textures) or a continuous swell
/// whose intensity curve is sampled from the envelope (sustained textures).
func analyzeHaptics(_ url: URL) -> HapticSuggestion? {
  guard let read = try? readChannels(url) else { return nil }
  let mono = toMono(read.channels)
  let sr = read.sampleRate

  // A steady ~1.1s window past the leading edge (fall back to the top).
  let (head, tail) = detectEdges(mono, sr: sr)
  var start = head
  var end = min(tail, start + Int(sr * 1.1))
  if end - start < Int(sr * 0.3) {
    start = 0
    end = min(mono.count, Int(sr * 1.1))
  }
  let seg = mono[start..<end]
  let dur = Double(end - start) / sr

  // 10 ms normalized RMS envelope.
  let hop = max(1, Int(sr * 0.01))
  let hopDur = Double(hop) / sr
  let env = rmsEnvelope(seg, win: hop)
  let emax = (env.max() ?? 1) + 1e-9
  let envN = env.map { $0 / emax }

  // Spectral-flux onsets: positive envelope jumps, peaks ≥45 ms apart. Each
  // onset's sharpness comes from a 20 ms attack window (the pop itself), not the
  // whole segment — so a crisp pop over a dull rumble reads as sharp.
  var flux = [Float](repeating: 0, count: envN.count)
  for i in 1..<envN.count { flux[i] = max(0, envN[i] - envN[i - 1]) }
  let fmean = flux.reduce(0, +) / Float(max(1, flux.count))
  var fvar: Float = 0
  for f in flux { fvar += (f - fmean) * (f - fmean) }
  let fstd = (fvar / Float(max(1, flux.count))).squareRoot()
  let thr = fmean + 0.8 * fstd
  let minGap = max(1, Int(0.045 / hopDur))
  let attack = max(1, Int(sr * 0.02))
  var onsets: [(t: Double, i: Float, s: Float)] = []
  var last = -minGap
  if flux.count > 2 {
    for k in 1..<(flux.count - 1)
    where flux[k] > thr && flux[k] >= flux[k - 1] && flux[k] >= flux[k + 1] && k - last >= minGap {
      let idx = start + k * hop
      let sharp = sharpnessOf(mono[idx..<min(end, idx + attack)])
      onsets.append((Double(k) * hopDur, min(1, envN[k]), sharp))
      last = k
    }
  }
  let density = Double(onsets.count) / dur
  // Gappiness: fraction of near-silent frames (spiky, percussive textures drop
  // between hits; a smooth swell never does).
  let gapFrac = Float(envN.filter { $0 < 0.35 }.count) / Float(max(1, envN.count))
  let medianSharp = onsets.isEmpty ? 0 : median(onsets.map { $0.s })
  // Transient if there ARE distinct events AND the texture is either spiky
  // (gaps) or bright (sharp attacks). A dense-but-smooth-and-dull swell (waves,
  // wind) stays continuous.
  let transientLike = density >= 5 && (gapFrac >= 0.25 || medianSharp >= 0.4)
  let overallSharp = sharpnessOf(seg)

  var pattern: [[String: Any]] = []
  var picks: [(t: Double, i: Float, s: Float)] = []
  if transientLike {
    picks = Array(onsets.sorted { $0.i > $1.i }.prefix(14)).sorted { $0.t < $1.t }
    for o in picks { pattern.append(ahapTransient(o.t, max(0.2, o.i), o.s)) }
  } else {
    pattern.append(ahapContinuous(dur, overallSharp))
    let pts = 12
    let cps = (0...pts).map { j -> [String: Any] in
      let frac = Double(j) / Double(pts)
      let idx = min(envN.count - 1, Int(frac * Double(envN.count - 1)))
      return ["Time": frac * dur, "ParameterValue": Double(envN[idx])]
    }
    pattern.append([
      "ParameterCurve": [
        "ParameterID": "HapticIntensityControl", "Time": 0.0, "ParameterCurveControlPoints": cps,
      ]
    ])
  }

  return HapticSuggestion(
    name: url.deletingPathExtension().lastPathComponent, dur: dur, startSec: Double(start) / sr,
    envN: envN, onsets: onsets, picks: picks, density: density, sharpness: overallSharp,
    gapFrac: gapFrac, transientLike: transientLike, pattern: pattern)
}

@discardableResult
func writeAHAP(_ s: HapticSuggestion, to outDir: String) -> String {
  let ahap: [String: Any] = [
    "Version": 1, "Metadata": ["Project": "Blankie", "Created": "blankifi haptics"],
    "Pattern": s.pattern,
  ]
  let outURL = URL(fileURLWithPath: outDir).appendingPathComponent("\(s.name).ahap")
  let data = try! JSONSerialization.data(withJSONObject: ahap, options: [.prettyPrinted, .sortedKeys])
  try! data.write(to: outURL)
  return outURL.path
}

/// `haptics <file>` (single) or `haptics --all` (every sound in sounds.json).
func cmdHaptics(_ args: [String]) {
  var outDir = FileManager.default.temporaryDirectory.path
  if let i = args.firstIndex(of: "--out"), i + 1 < args.count { outDir = args[i + 1] }

  if args.contains("--all") {
    var soundsDir = "Blankie/Resources/Sounds"
    var jsonPath = "Blankie/Resources/sounds.json"
    if let i = args.firstIndex(of: "--sounds-dir"), i + 1 < args.count { soundsDir = args[i + 1] }
    if let i = args.firstIndex(of: "--json"), i + 1 < args.count { jsonPath = args[i + 1] }
    guard let data = FileManager.default.contents(atPath: jsonPath),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sounds = obj["sounds"] as? [[String: Any]]
    else { fail("cannot read \(jsonPath)") }
    print("sound            current    derived        dens  shrp  gap   envelope")
    print(String(repeating: "─", count: 96))
    for s in sounds {
      guard let fn = s["fileName"] as? String else { continue }
      let cur = (s["hapticVoice"] as? String) ?? "-"
      let url = URL(fileURLWithPath: "\(soundsDir)/\(fn).m4a")
      guard let a = analyzeHaptics(url) else {
        print("\(fn.padding(toLength: 16, withPad: " ", startingAt: 0)) (cannot read)")
        continue
      }
      writeAHAP(a, to: outDir)
      let derived = a.transientLike ? "transient×\(a.picks.count)" : "continuous"
      print(
        String(
          format: "%@ %@ %@ %4.1f  %.2f  %.2f  %@",
          fn.padding(toLength: 16, withPad: " ", startingAt: 0),
          cur.padding(toLength: 10, withPad: " ", startingAt: 0),
          derived.padding(toLength: 14, withPad: " ", startingAt: 0),
          a.density, a.sharpness, a.gapFrac, sparkline(downsampled(a.envN, 40))))
    }
    print("\nwrote \(sounds.count) .ahap files to \(outDir)")
    return
  }

  guard let path = args.first else { fail("usage: haptics <file> [--out DIR]  |  haptics --all") }
  guard let a = analyzeHaptics(URL(fileURLWithPath: path)) else { fail("cannot read \(path)") }
  let out = writeAHAP(a, to: outDir)
  print(
    "── \(a.name)   window \(String(format: "%.2f", a.dur))s @ \(String(format: "%.1f", a.startSec))s ──"
  )
  print("   env  \(sparkline(downsampled(a.envN, 64)))")
  print(
    String(
      format: "   onsets %d (%.1f/sec)   sharpness %.2f   gap %.2f   → %@", a.onsets.count, a.density,
      a.sharpness, a.gapFrac,
      a.transientLike ? "TRANSIENT (\(a.picks.count) taps)" : "CONTINUOUS (envelope swell)"))
  if a.transientLike {
    for o in a.picks { print(String(format: "      t=%.3f  i=%.2f  s=%.2f", o.t, o.i, o.s)) }
  }
  print("   wrote \(out)")
}

@main
struct BlankIFI {
  static func main() async {
    let argv = Array(CommandLine.arguments.dropFirst())
    guard let cmd = argv.first else {
      print(
        """
        blankifi — Blankie audio toolkit
          analyze   <file>
          loop      <file> [out-prefix]
          fix       <in> <out> [--xfade-ms 250] [--bitrate 192000]
          convert   <in> <out.m4a> [--bitrate 192000]
          reanalyze [--write] [--json PATH] [--sounds-dir DIR]
          haptics   <file> [--out DIR]  |  haptics --all [--out DIR]
        """)
      return
    }
    let rest = Array(argv.dropFirst())
    switch cmd {
    case "analyze": await cmdAnalyze(rest)
    case "loop": cmdLoop(rest)
    case "fix": cmdFix(rest)
    case "convert": cmdConvert(rest)
    case "reanalyze": await cmdReanalyze(rest)
    case "haptics": cmdHaptics(rest)
    default: fail("unknown subcommand '\(cmd)'")
    }
  }
}
