//
//  SoundFilterPad.swift
//  Blankie
//
//  Created by Cody Bromley on 11/23/26.
//

import CoreHaptics
import SwiftUI

/// SPIKE: a Photographic Styles–style pad that shapes one sound's tone live.
/// X works on the highs (smooth on the left, clear on the right). Y works on the
/// lows (less bass at the bottom, more at the top). The two are independent.
/// Center is the untouched sound. Throwaway: no persistence, no VoiceOver.
struct SoundFilterPad: View {
  let sound: Sound

  @State private var highs: Float = 0
  @State private var lows: Float = 0
  @State private var dragStart: CGPoint?
  @State private var dotIndex = DotIndex(x: 0, y: 0)
  @State private var atWall = false
  @State private var haptics = FilterPadHaptics()

  private static let dotsPerSide = 11
  private static var half: Int { dotsPerSide / 2 }
  /// Snaps to center within this distance, a soft detent at "untouched."
  private static let centerDetent: Float = 0.06

  private struct DotIndex: Equatable {
    var x: Int
    var y: Int
  }

  var body: some View {
    VStack(spacing: 14) {
      pad

      // Always visible, so the way back is on screen before the first touch.
      Button {
        reset()
      } label: {
        Text(verbatim: "Reset to Original")
      }
      .buttonStyle(.bordered)
      .disabled(highs == 0 && lows == 0)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .onAppear {
      highs = sound.toneHighs
      lows = sound.toneLows
      dotIndex = index(highs: highs, lows: lows)
    }
  }

  // MARK: - Pieces

  /// Warm and deep on the darker side, cool and lighter on the brighter side.
  private var background: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.36, green: 0.30, blue: 0.27),
          Color(red: 0.30, green: 0.31, blue: 0.40),
        ],
        startPoint: .leading, endPoint: .trailing)
      LinearGradient(
        colors: [.white.opacity(0.06), .black.opacity(0.45)],
        startPoint: .top, endPoint: .bottom)
    }
  }

  private func dots(side: CGFloat) -> some View {
    Canvas { context, size in
      let count = Self.dotsPerSide
      let inset = size.width * 0.1
      let step = (size.width - inset * 2) / CGFloat(count - 1)
      let puck = position(in: size.width)
      for row in 0..<count {
        for column in 0..<count {
          let center = CGPoint(
            x: inset + CGFloat(column) * step, y: inset + CGFloat(row) * step)
          let onAxis = row == Self.half || column == Self.half
          // Dots near the puck brighten a little, like light spilling off it.
          let distance = hypot(center.x - puck.x, center.y - puck.y) / size.width
          let glow = max(0, 0.35 - distance) * 1.2
          let opacity = (onAxis ? 0.85 : 0.28) + glow
          let radius: CGFloat = onAxis ? 2.6 : 2.2
          context.fill(
            Path(
              ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2)),
            with: .color(.white.opacity(min(opacity, 1))))
        }
      }
    }
    .allowsHitTesting(false)
  }

  private var pad: some View {
    GeometryReader { proxy in
      let side = proxy.size.width
      ZStack {
        background
        dots(side: side)
        edgeWords
        puck
          .position(position(in: side))
      }
      .clipShape(.rect(cornerRadius: side * 0.17, style: .continuous))
      .contentShape(.rect(cornerRadius: side * 0.17, style: .continuous))
      .gesture(drag(side: side))
      .onTapGesture(count: 2) { reset() }
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: 300)
  }

  /// Placeholder words. Each names what that direction does.
  private var edgeWords: some View {
    ZStack {
      VStack {
        Text(verbatim: "MORE BASS")
        Spacer()
        Text(verbatim: "LESS BASS")
      }
      HStack {
        Text(verbatim: "SMOOTH")
          .fixedSize()
          .rotationEffect(.degrees(-90))
          .frame(width: 14)
        Spacer()
        Text(verbatim: "CLEAR")
          .fixedSize()
          .rotationEffect(.degrees(90))
          .frame(width: 14)
      }
    }
    .font(.system(size: 9, weight: .semibold))
    .tracking(1.4)
    .foregroundStyle(.white.opacity(0.45))
    .padding(5)
    .allowsHitTesting(false)
  }

  private var puck: some View {
    Circle()
      .fill(.white)
      .frame(width: 30, height: 30)
      .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
      .allowsHitTesting(false)
  }

  // MARK: - Geometry

  private func position(in side: CGFloat) -> CGPoint {
    let inset = side * 0.1
    let span = side / 2 - inset
    return CGPoint(
      x: side / 2 + CGFloat(highs) * span,
      y: side / 2 - CGFloat(lows) * span)
  }

  private func index(highs: Float, lows: Float) -> DotIndex {
    let half = Float(Self.half)
    return DotIndex(x: Int((highs * half).rounded()), y: Int((lows * half).rounded()))
  }

  // MARK: - Interaction

  /// Relative drag, like Photographic Styles: the puck moves by the finger's
  /// travel, so touching down never makes it jump.
  private func drag(side: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        let start = dragStart ?? CGPoint(x: CGFloat(highs), y: CGFloat(lows))
        if dragStart == nil {
          dragStart = start
          haptics.beginTexture(highs: highs, lows: lows)
        }
        let span = side / 2 - side * 0.1
        var newHighs = Float(start.x + value.translation.width / span)
        var newLows = Float(start.y - value.translation.height / span)
        newHighs = max(-1, min(1, newHighs))
        newLows = max(-1, min(1, newLows))
        if abs(newHighs) < Self.centerDetent { newHighs = 0 }
        if abs(newLows) < Self.centerDetent { newLows = 0 }
        apply(highs: newHighs, lows: newLows)
      }
      .onEnded { _ in
        dragStart = nil
        haptics.endTexture()
      }
  }

  private func reset() {
    guard highs != 0 || lows != 0 else { return }
    withAnimation(.spring(duration: 0.3)) {
      apply(highs: 0, lows: 0)
    }
  }

  private func apply(highs newHighs: Float, lows newLows: Float) {
    let wasCentered = highs == 0 && lows == 0
    highs = newHighs
    lows = newLows
    sound.setTone(highs: newHighs, lows: newLows)

    let isCentered = newHighs == 0 && newLows == 0
    let newIndex = index(highs: newHighs, lows: newLows)
    let hitWall = abs(newHighs) == 1 || abs(newLows) == 1
    if isCentered && !wasCentered {
      haptics.detent()
    } else if hitWall && !atWall {
      haptics.wall()
    } else if newIndex != dotIndex {
      haptics.tick(highs: newHighs)
    }
    dotIndex = newIndex
    atWall = hitWall
    haptics.updateTexture(highs: newHighs, lows: newLows)
  }
}

// MARK: - Haptics

/// SPIKE: the pad's feel. While dragging, a faint continuous texture follows the
/// tone: dull on the smooth side, crisp on the clear side, fuller with more bass,
/// fainter with less. Crossing a dot ticks (dull to crisp, left to right), center
/// lands with a soft clunk, and the walls bump.
///
/// Own engine on its own session (`playsHapticsOnly`): sharing the app's
/// `.playback` session silently swallows haptics. The texture player is retained
/// for the length of the drag, or it cuts off.
@MainActor
final class FilterPadHaptics {
  private var engine: CHHapticEngine?
  private var texture: CHHapticAdvancedPatternPlayer?

  init() {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    let engine = try? CHHapticEngine()
    engine?.playsHapticsOnly = true
    engine?.isAutoShutdownEnabled = true
    self.engine = engine
  }

  func beginTexture(highs: Float, lows: Float) {
    guard let engine, start() else { return }
    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
      ],
      relativeTime: 0, duration: 100)
    guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
      let player = try? engine.makeAdvancedPlayer(with: pattern)
    else { return }
    texture = player
    updateTexture(highs: highs, lows: lows)
    try? player.start(atTime: CHHapticTimeImmediate)
  }

  func updateTexture(highs: Float, lows: Float) {
    guard let texture else { return }
    // Barely there at center, so the feel grows with how far the sound has moved.
    let distance = min(1, hypot(highs, lows))
    let intensity = (0.04 + 0.22 * distance + 0.18 * max(0, lows) - 0.06 * max(0, -lows))
    let parameters = [
      CHHapticDynamicParameter(
        parameterID: .hapticIntensityControl, value: max(0, min(1, intensity)), relativeTime: 0),
      CHHapticDynamicParameter(
        parameterID: .hapticSharpnessControl, value: highs * 0.45, relativeTime: 0),
    ]
    try? texture.sendParameters(parameters, atTime: CHHapticTimeImmediate)
  }

  func endTexture() {
    try? texture?.stop(atTime: CHHapticTimeImmediate)
    texture = nil
  }

  func tick(highs: Float) {
    transient(intensity: 0.45, sharpness: 0.5 + highs * 0.45)
  }

  func detent() {
    transient(intensity: 0.8, sharpness: 0.2)
  }

  func wall() {
    transient(intensity: 1, sharpness: 0.7)
  }

  private func transient(intensity: Float, sharpness: Float) {
    guard let engine, start() else { return }
    let event = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: 0)
    guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
      let player = try? engine.makePlayer(with: pattern)
    else { return }
    try? player.start(atTime: CHHapticTimeImmediate)
  }

  /// Auto-shutdown and resets stop the engine. Starting a running one is cheap.
  private func start() -> Bool {
    guard let engine else { return false }
    do {
      try engine.start()
      return true
    } catch {
      return false
    }
  }
}

// MARK: - Preview

#Preview("Filter Pad") {
  SoundPrototypeHarness { sound in
    SoundFilterPad(sound: sound)
  }
  .preferredColorScheme(.dark)
}

/// Plays a built-in sound through preview mode so a prototype control can be
/// heard and felt from the canvas on a device.
struct SoundPrototypeHarness<Content: View>: View {
  /// Starts the sound as soon as the preview appears.
  var autoplay = false
  @ViewBuilder let content: (Sound) -> Content

  @State private var selected: Sound?
  @State private var isPlaying = false

  private var sounds: [Sound] {
    AudioManager.shared.sounds.filter { !$0.isCustom && !($0 is KaleidoscopeSound) }
  }

  var body: some View {
    VStack(spacing: 20) {
      Picker(selection: $selected) {
        ForEach(sounds) { sound in
          Text(verbatim: sound.title).tag(Optional(sound))
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.menu)

      Button {
        toggle()
      } label: {
        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
          .font(.title2)
          .frame(width: 56, height: 56)
      }
      .buttonStyle(.glass)

      if let selected {
        content(selected)
          .id(selected.id)
      }
    }
    .padding()
    .onAppear {
      let first = sounds.first { $0.fileName == "rain" } ?? sounds.first
      selected = first
      if autoplay, let first {
        AudioManager.shared.enterPreviewMode(for: first)
        isPlaying = true
      }
    }
    .onChange(of: selected) { old, new in
      guard isPlaying, let new else { return }
      old?.setTone(highs: 0, lows: 0)
      old?.setSynthFilter(mode: .off, cutoff: 1_000, resonance: 0)
      old?.setGraphicEQ(gains: [])
      AudioManager.shared.exitPreviewMode(resuming: false)
      AudioManager.shared.enterPreviewMode(for: new)
    }
  }

  private func toggle() {
    guard let selected else { return }
    if isPlaying {
      AudioManager.shared.exitPreviewMode(resuming: false)
    } else {
      AudioManager.shared.enterPreviewMode(for: selected)
    }
    isPlaying.toggle()
  }
}
