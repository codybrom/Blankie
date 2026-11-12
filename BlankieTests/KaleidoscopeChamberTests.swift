//
//  KaleidoscopeChamberTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 11/10/26.
//

import Foundation
import Testing

@testable import Blankie

/// The glass a recipe builds for its kaleidoscope, and how that glass tumbles.
@Suite struct KaleidoscopeChamberTests {

  private static func recipe(
    fileName: String = "kaleidoscope-test", layers layerCount: Int = 5, tones toneCount: Int = 4
  ) -> KaleidoscopeRecipe {
    let swell = (0..<32).map { 20 * log10(1.0 + Double($0) / 32.0) }
    // Small, so the tumbling tests stay quick in a debug build.
    let layers = (0..<layerCount).map { index in
      KaleidoscopeRecipe.Layer(
        name: "Layer \(index)",
        tones: (0..<toneCount).map { tone in
          KaleidoscopeRecipe.Tone(
            hz: 55 * pow(2, Double(index)) + Double(tone), db: -Double(tone) * 3, wobble: swell)
        })
    }
    return KaleidoscopeRecipe(
      title: "Test Kaleidoscope", fileName: fileName, systemIconName: "sparkles", lufs: -23,
      source: KaleidoscopeRecipe.Source(title: "Test", author: "Test", license: "cc0", url: ""),
      attackSec: 3, loopSec: 32, layers: layers)
  }

  // MARK: - Chamber

  @Test func everyToneGetsItsShareOfGlass() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe())
    #expect(chamber.pieces.count == 5 * 4 * KaleidoscopeChamber.piecesPerTone)
    #expect(Set(chamber.pieces.map(\.tone)) == Set(0..<20))
  }

  @Test func sameSoundBuildsTheSameGlass() {
    let first = KaleidoscopeChamber(recipe: Self.recipe())
    let second = KaleidoscopeChamber(recipe: Self.recipe())
    #expect(first.folds == second.folds)
    #expect(first.pieces.map(\.radius) == second.pieces.map(\.radius))
    #expect(first.pieces.map(\.seed) == second.pieces.map(\.seed))
    let other = KaleidoscopeChamber(recipe: Self.recipe(fileName: "kaleidoscope-other"))
    #expect(first.pieces.map(\.seed) != other.pieces.map(\.seed))
  }

  @Test func glassFillsItsShareOfTheChamber() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe())
    let glass = chamber.pieces.reduce(0) { $0 + .pi * $1.radius * $1.radius }
    let room = .pi * KaleidoscopeChamber.wall * KaleidoscopeChamber.wall
    #expect(abs(glass / room - KaleidoscopeChamber.fill * 0.84) < 0.001)
    // Nothing is a speck beside its neighbors.
    let radii = chamber.pieces.map(\.radius)
    #expect((radii.max() ?? 0) / (radii.min() ?? 1) < 4)
  }

  @Test func soundTurnsTheChamberFasterWhenItMoves() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe())
    #expect(chamber.turn(at: 0) == 0)
    var last = 0.0
    for second in 1...64 {
      let turn = chamber.turn(at: Double(second))
      #expect(turn > last)
      last = turn
    }
    // One trip around the loop turns it the same amount every time.
    let loop = chamber.turn(at: 32) - chamber.turn(at: 0)
    #expect(abs((chamber.turn(at: 64) - chamber.turn(at: 32)) - loop) < 1e-9)
  }

  // MARK: - Tumbler

  @Test func glassStaysInsideTheChamber() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe())
    let tumbler = KaleidoscopeTumbler(chamber: chamber)
    for step in 0..<600 {
      // Still, then a slow turn, then a hard spin each way.
      tumbler.step(turnSpeed: step < 150 ? 0 : (step < 300 ? 0.05 : (step < 450 ? 2.4 : -2.4)))
    }
    for body in tumbler.bodies {
      #expect(body.x.isFinite && body.y.isFinite && body.angle.isFinite)
      #expect(hypot(body.x, body.y) <= KaleidoscopeChamber.wall - body.radius + 1e-6)
    }
  }

  /// The bundled recipes run to about 137 tones, which is over 400 pieces of glass.
  @Test func aFullChamberStaysInsideAndApart() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe(layers: 9, tones: 15))
    #expect(chamber.pieces.count == 405)
    let tumbler = KaleidoscopeTumbler(chamber: chamber)
    for step in 0..<240 { tumbler.step(turnSpeed: step < 120 ? 0.5 : -2.4) }
    // A hard spin lets the wall's grip slide a piece a hair past it, and no further.
    let past = tumbler.bodies.map { hypot($0.x, $0.y) + $0.radius - KaleidoscopeChamber.wall }
    #expect(past.allSatisfy { $0.isFinite })
    #expect((past.max() ?? 0) < 0.01)
    // Neighbors are pushed apart, so no two pieces sit deep inside each other.
    var deepest = 0.0
    for first in tumbler.bodies.indices {
      for second in (first + 1)..<tumbler.bodies.count {
        let a = tumbler.bodies[first]
        let b = tumbler.bodies[second]
        deepest = max(deepest, (a.radius + b.radius - hypot(b.x - a.x, b.y - a.y)) / (a.radius + b.radius))
      }
    }
    #expect(deepest < 0.5)
  }

  @Test func settledGlassLiesStill() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe())
    let tumbler = KaleidoscopeTumbler(chamber: chamber)
    for _ in 0..<600 { tumbler.step(turnSpeed: 0) }
    let before = tumbler.bodies
    for _ in 0..<60 { tumbler.step(turnSpeed: 0) }
    let drift = zip(before, tumbler.bodies).map { hypot($1.x - $0.x, $1.y - $0.y) }
    #expect((drift.max() ?? 0) < 0.02)
  }

  @Test func turningCarriesThePileWithIt() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe())
    let tumbler = KaleidoscopeTumbler(chamber: chamber)
    let before = tumbler.bodies
    // A quarter second of turning at one radian a second.
    for _ in 0..<15 { tumbler.step(turnSpeed: 1) }
    var followed = 0
    for (was, now) in zip(before, tumbler.bodies) where hypot(was.x, was.y) > 0.3 {
      var turned = atan2(now.y, now.x) - atan2(was.y, was.x)
      turned -= 2 * .pi * (turned / (2 * .pi)).rounded()
      if turned > 0.1 { followed += 1 }
    }
    #expect(Double(followed) > Double(before.count) * 0.6)
  }

  @Test func aFlickCannotWhipTheGlassAround() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe())
    let tumbler = KaleidoscopeTumbler(chamber: chamber)
    let start = Date(timeIntervalSince1970: 0)
    tumbler.advance(to: start, turn: 0)
    let before = tumbler.bodies
    // The hand jumps a full turn in one frame.
    tumbler.advance(to: start.addingTimeInterval(1.0 / 30), turn: 2 * .pi)
    let moved = zip(before, tumbler.bodies).map { hypot($1.x - $0.x, $1.y - $0.y) }
    #expect((moved.max() ?? 0) < KaleidoscopeChamber.wall * KaleidoscopeTumbler.fastestTurn / 30 + 0.05)
  }

  // MARK: - Drawing

  @Test func onlyGlassInTheMirrorsWedgeIsDrawn() {
    let chamber = KaleidoscopeChamber(recipe: Self.recipe())
    let tumbler = KaleidoscopeTumbler(chamber: chamber)
    let sprites = chamber.sprites(
      at: 10, in: tumbler, apex: CGPoint(x: 200, y: 0), axis: CGVector(dx: 0, dy: 1), span: 370,
      reach: 600)
    #expect(!sprites.isEmpty)
    #expect(sprites.count < chamber.pieces.count / 2)
    let slope = tan(.pi / Double(chamber.folds) / 2)
    for sprite in sprites {
      let along = sprite.center.y
      let across = abs(sprite.center.x - 200)
      #expect(along > -sprite.radius * 2 && along < 600 + sprite.radius * 2)
      #expect(across < max(along, 0) * slope + sprite.radius * 2)
      #expect(sprite.glow >= 0 && sprite.glow <= 1)
    }
  }
}
