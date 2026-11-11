//
//  KaleidoscopePlayerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 11/2/26.
//

import Foundation
import Testing

@testable import Blankie

/// Runs `KaleidoscopePlayer.render`, the same function the source node calls, with
/// test-owned voices so every result is deterministic.
@Suite struct KaleidoscopePlayerTests {

  private static func testRecipe() -> KaleidoscopeRecipe {
    // The second tone swells 1→2 across its 32-second motion loop.
    let swell = (0..<32).map { 20 * log10(1.0 + Double($0) / 32.0) }
    return KaleidoscopeRecipe(
      title: "Test Kaleidoscope",
      fileName: "kaleidoscope-test",
      systemIconName: "sparkles",
      lufs: -23,
      source: KaleidoscopeRecipe.Source(title: "Test", author: "Test", license: "cc0", url: ""),
      attackSec: 3.0,
      loopSec: 32,
      layers: [
        KaleidoscopeRecipe.Layer(
          name: "Test",
          tones: [
            KaleidoscopeRecipe.Tone(hz: 110, db: 0, wobble: [Double](repeating: 0, count: 32)),
            KaleidoscopeRecipe.Tone(hz: 220, db: -6, wobble: swell),
          ])
      ])
  }

  private static func render(
    frames: Int, from startFrame: Int64, seed: UInt64 = 7, recipe: KaleidoscopeRecipe = testRecipe()
  ) -> (left: [Float], right: [Float]) {
    let state = KaleidoscopePlayer.renderState(for: recipe, sampleRate: 48_000)
    var rng = seed
    var voices = KaleidoscopePlayer.VoiceState.seeded(count: state.increments.count, rng: &rng)
    var left = [Float](repeating: 0, count: frames)
    var right = [Float](repeating: 0, count: frames)
    left.withUnsafeMutableBufferPointer { leftBuffer in
      right.withUnsafeMutableBufferPointer { rightBuffer in
        KaleidoscopePlayer.render(
          state: state, voices: &voices, startFrame: startFrame, volume: 1,
          left: leftBuffer, right: rightBuffer)
      }
    }
    return (left, right)
  }

  // MARK: - Recipes

  @Test @MainActor func bundledRecipesDecode() {
    let recipes = KaleidoscopeRecipe.bundled
    #expect(recipes.map(\.fileName) == KaleidoscopeRecipe.bundledFileNames)
    for recipe in recipes {
      #expect(recipe.source.author == "Matio888")
      #expect(License(rawValue: recipe.source.license.lowercased()) == .ccBy4)
      #expect(!recipe.layers.isEmpty)
      for layer in recipe.layers {
        #expect(!layer.tones.isEmpty)
        #expect(!layer.arc.isEmpty)
        #expect(!layer.wobbleSeed.isEmpty)
        #expect(layer.tones.allSatisfy { $0.wobbleDB > 0 && !$0.wander.isEmpty })
      }
    }
  }

  @Test @MainActor func motionSumsArcWanderAndWobble() throws {
    let json = #"""
      {"name": "Sub", "arc": [0, 4], "wobbleDepth": 0.5,
       "tones": [{"hz": 55, "db": 0, "wander": [2, 2], "wobble": [0, 2, 0, -2]}]}
      """#
    let layer = try JSONDecoder().decode(KaleidoscopeRecipe.Layer.self, from: Data(json.utf8))
    let motion = layer.tones[0].motion(in: layer, index: 0, loopSec: 4)
    // Arc glides 0, 2, 4, 2 and loops. Wander adds 2. Wobble adds half of itself.
    // The shape is kept, and the whole is leveled to an average power of 1.
    let decibels = motion.map { 20 * log10(Double($0)) }
    for (got, want) in zip(decibels, [2.0, 5, 6, 3]) {
      #expect(abs((got - decibels[0]) - (want - 2)) < 1e-4)
    }
    let power = motion.reduce(0) { $0 + Double($1 * $1) } / 4
    #expect(abs(power - 1) < 1e-5)
  }

  @Test @MainActor func toneWithoutMotionHoldsSteady() {
    let layer = KaleidoscopeRecipe.Layer(name: "Sub", tones: [.init(hz: 55, db: 0)])
    #expect(layer.tones[0].motion(in: layer, index: 0, loopSec: 60).isEmpty)
  }

  @Test func sameSeedGrowsTheSameWobble() {
    let grow = { (seed: String) in
      KaleidoscopeRecipe.Tone.grownWobble(seed: seed, loopSec: 300, paceSec: 7, slowPoints: 20)
    }
    let wobble = grow("golden shimmer#3")
    #expect(wobble == grow("golden shimmer#3"))
    #expect(wobble != grow("golden shimmer#4"))
    let mean = wobble.reduce(0, +) / 300
    let spread = (wobble.reduce(0) { $0 + $1 * $1 } / 300).squareRoot()
    #expect(wobble.count == 300 && abs(mean) < 1e-9 && abs(spread - 1) < 1e-9)
  }

  @Test func wobbleSizeFollowsTheTone() {
    var layer = KaleidoscopeRecipe.Layer(
      name: "Sub", wobbleSeed: "test", tones: [.init(hz: 55, db: 0, wobbleDB: 6)])
    let swing = { (layer: KaleidoscopeRecipe.Layer) -> Double in
      let decibels = layer.tones[0].motion(in: layer, index: 0, loopSec: 300)
        .map { 20 * log10(Double($0)) }
      let mean = decibels.reduce(0, +) / 300
      return (decibels.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 300).squareRoot()
    }
    #expect(abs(swing(layer) - 6) < 1e-3)
    layer.wobbleDepth = 0.5
    #expect(abs(swing(layer) - 3) < 1e-3)
  }

  @Test @MainActor func layerTuningDefaultsToAsMeasured() throws {
    let json = #"{"name": "Sub", "tones": [{"hz": 55, "db": 0}]}"#
    let layer = try JSONDecoder().decode(KaleidoscopeRecipe.Layer.self, from: Data(json.utf8))
    #expect(layer.gainDB == 0 && layer.motionDepth == 1 && layer.motionSpeed == 1)
    #expect(layer.detuneCents == 6 && layer.panWidth == 0.8)
    #expect(layer.arcDepth == 1 && layer.wanderDepth == 1 && layer.wobbleDepth == 1)
    #expect(layer.arc.isEmpty && layer.tones[0].wobble.isEmpty)
  }

  // MARK: - Render state

  @Test func renderStateGivesEachToneTwoVoices() {
    let state = KaleidoscopePlayer.renderState(for: Self.testRecipe(), sampleRate: 48_000)
    #expect(state.increments.count == 4)
    #expect(state.motion.count == 2)
    #expect(state.motion[1].count == 32)
    // Each tone's level is split evenly across its two voices.
    #expect(abs(state.levels[0] + state.levels[1] - 1.0) < 0.001)
    #expect(abs(Double(state.levels[2] + state.levels[3]) - pow(10, -6.0 / 20)) < 0.001)
  }

  @Test func denseRecipesScaleDownToTargetLevelSum() {
    var recipe = Self.testRecipe()
    recipe.layers[0].tones = (1...10).map { KaleidoscopeRecipe.Tone(hz: Double($0) * 100, db: 0) }
    let state = KaleidoscopePlayer.renderState(for: recipe, sampleRate: 48_000)
    let sum = state.levels.reduce(0, +)
    #expect(abs(Double(sum) - KaleidoscopePlayer.targetLevelSum) < 0.001)
  }

  @Test func layerGainScalesItsTones() {
    var recipe = Self.testRecipe()
    recipe.layers[0].gainDB = -20
    let state = KaleidoscopePlayer.renderState(for: recipe, sampleRate: 48_000)
    #expect(abs(state.levels[0] + state.levels[1] - 0.1) < 0.001)
  }

  @Test func motionDepthAndSpeedShapeTheEnvelope() {
    var recipe = Self.testRecipe()
    recipe.layers[0].motionDepth = 0
    var state = KaleidoscopePlayer.renderState(for: recipe, sampleRate: 48_000)
    #expect(KaleidoscopePlayer.envelopeGain(state: state, partial: 1, absoluteFrame: 480_000) == 1)
    recipe.layers[0].motionDepth = 1
    recipe.layers[0].motionSpeed = 2
    state = KaleidoscopePlayer.renderState(for: recipe, sampleRate: 48_000)
    // Double speed reaches second 8 after four seconds, a quarter louder than the start.
    let gain = KaleidoscopePlayer.envelopeGain(state: state, partial: 1, absoluteFrame: 192_000)
    #expect(abs(gain / Double(state.motion[1][0]) - 1.25) < 1e-5)
  }

  @Test func earLagDelaysTheRightEarsMotion() {
    // One tone that fades steadily, so a late right ear is the louder one.
    var recipe = Self.testRecipe()
    let fade = (0..<32).map { 20 * log10(Double(32 - $0) / 32) }
    recipe.layers[0].tones = [KaleidoscopeRecipe.Tone(hz: 220, db: 0, wobble: fade)]
    recipe.layers[0].panWidth = 0
    let power = { (samples: [Float]) in samples.reduce(0) { $0 + Double($1 * $1) } }
    recipe.earLagSec = 4
    let lagged = Self.render(frames: 48_000, from: 480_000, recipe: recipe)
    #expect(power(lagged.right) > power(lagged.left) * 1.2)
  }

  // MARK: - Rendering

  @Test func renderIsDeterministic() {
    let a = Self.render(frames: 2048, from: 200_000)
    let b = Self.render(frames: 2048, from: 200_000)
    #expect(a.left == b.left)
    #expect(a.right == b.right)
  }

  @Test func renderStaysBounded() {
    let out = Self.render(frames: 48_000, from: 0, seed: 11)
    #expect(out.left.allSatisfy { $0.isFinite && abs($0) <= 1 })
    #expect(out.right.allSatisfy { $0.isFinite && abs($0) <= 1 })
  }

  @Test func renderStartsSilentThroughAttack() {
    let out = Self.render(frames: 1, from: 0, seed: 13)
    #expect(out.left == [0] && out.right == [0])
  }

  @Test func channelsDiffer() {
    let out = Self.render(frames: 512, from: 200_000, seed: 17)
    #expect(out.left != out.right)
  }

  // MARK: - Envelopes

  @Test func envelopeGainInterpolatesAndWraps() {
    let state = KaleidoscopePlayer.renderState(for: Self.testRecipe(), sampleRate: 48_000)
    // Halfway between the first second and the next, which is 1/32 louder.
    let first = Double(state.motion[1][0])
    let mid = KaleidoscopePlayer.envelopeGain(state: state, partial: 1, absoluteFrame: 24_000)
    #expect(abs(mid / first - (1.0 + 0.5 / 32)) < 1e-5)
    // One full loop later reads the same value.
    let wrapped = KaleidoscopePlayer.envelopeGain(
      state: state, partial: 1, absoluteFrame: 24_000 + 32 * 48_000)
    #expect(abs(wrapped - mid) < 1e-9)
  }

  @Test func fastSinMatchesSin() {
    for step in 0..<1000 {
      let x = Double(step) / 1000 * 2 * .pi
      #expect(abs(KaleidoscopePlayer.fastSin(x) - sin(x)) < 1e-8)
    }
  }
}
