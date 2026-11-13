//
//  KaleidoscopeChamber.swift
//  Blankie
//
//  Created by Cody Bromley on 11/10/26.
//

import Foundation

/// The glass a recipe puts in a kaleidoscope's chamber. Each piece is
/// one of the sound's tones, and glows as that tone swells.
nonisolated struct KaleidoscopeChamber {
  struct Piece {
    var tone: Int
    var radius: Double
    var color: [Float]
    /// 0 tumbled chunk, 1 cut gem, 2 rod.
    var kind: Double
    var seed: Double
    var depth: Double
    /// How much it shows, from 0 to 1. Half the glass is nearly clear filler, which
    /// keeps the chamber packed while leaving dark space between the colored pieces.
    var presence: Double
  }

  /// Pieces of glass for each tone. More pieces means smaller ones.
  static let piecesPerTone = 3
  /// The chamber's inner radius, in spans of the picture.
  static let wall = 1.62
  /// How much of the chamber the glass fills. Nearly full, the pile turns as one
  /// with the chamber, so the picture follows a finger exactly. The gap left at the
  /// top is where pieces tumble.
  static let fill = 0.85

  /// Sets of glass colors that sit well together. The last of each is the clear glass.
  static let palettes: [[[Float]]] = [
    [[0.62, 0.36, 0.86], [0.20, 0.36, 0.92], [0.95, 0.45, 0.62], [0.90, 0.94, 0.97]],
    [[0.98, 0.66, 0.18], [0.88, 0.14, 0.22], [0.60, 0.70, 0.25], [0.97, 0.93, 0.86]],
    [[0.12, 0.72, 0.42], [0.10, 0.66, 0.70], [0.95, 0.80, 0.35], [0.90, 0.96, 0.94]],
    [[0.20, 0.36, 0.92], [0.35, 0.82, 0.90], [0.48, 0.30, 0.90], [0.90, 0.94, 0.98]],
    [[0.88, 0.14, 0.22], [0.95, 0.45, 0.62], [0.98, 0.66, 0.18], [0.75, 0.72, 0.70]],
    [[0.55, 0.52, 0.50], [0.95, 0.80, 0.35], [0.10, 0.66, 0.70], [0.93, 0.93, 0.93]],
  ]

  let state: KaleidoscopePlayer.RenderState
  let pieces: [Piece]
  let folds: Int
  let wash: [Float]
  let seed: UInt64
  /// Radians a second the chamber turns while the sound moves at its usual rate.
  let turnRate: Double
  /// Running total of how much the sound has moved by each second of its loop.
  let motionClock: [Double]

  init(recipe: KaleidoscopeRecipe) {
    // A sample rate of 1 makes the state's frames whole seconds.
    state = KaleidoscopePlayer.renderState(for: recipe, sampleRate: 1)
    var seed = (recipe.glassSeed ?? recipe.fileName).utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) {
      ($0 ^ UInt64($1)) &* 0x100_0000_01B3
    }
    self.seed = seed
    folds = [6, 7, 8][Int(seed % 3)]
    // About one turn every minute and a half.
    turnRate = recipe.driftSpeed * 2 * .pi / 90
    let palette = Self.palettes[Int((seed >> 16) % UInt64(Self.palettes.count))]
    wash = palette[0]
    motionClock = Self.motionClock(for: state)

    // Low layers are large tumbled chunks. Higher ones are cut gems and rods.
    let kinds: [Double] = [0, 0, 0, 1, 0, 2, 1, 0, 1]
    var all = [Piece]()
    var firstTone = 0
    for (index, layer) in recipe.layers.enumerated() {
      let height = Double(index) / Double(max(recipe.layers.count - 1, 1))
      let loudest = layer.tones.indices.sorted { layer.tones[$0].db > layer.tones[$1].db }
      for (rank, tone) in loudest.enumerated() {
        let unit = { KaleidoscopePlayer.nextUnit(&seed) }
        for copy in 0..<Self.piecesPerTone {
          let clear = height > 0.7 && (rank + copy) % 2 == 0
          all.append(
            Piece(
              tone: firstTone + tone,
              // Sizes stay within about three to one, so nothing is a speck.
              radius: (0.115 - 0.05 * height) * (1 - 0.02 * Double(rank))
                * (1 - 0.06 * Double(copy)),
              color: clear ? palette[3] : palette[(index + rank + copy) % 3],
              kind: kinds[(index + copy) % kinds.count],
              seed: unit(),
              depth: min(max(1 - height * 0.7 - unit() * 0.3, 0), 1),
              presence: copy == 0 || (copy == 1 && rank.isMultiple(of: 2)) ? 1 : 0.1))
        }
      }
      firstTone += layer.tones.count
    }
    // Size the glass so it fills its share of the chamber.
    let area = all.reduce(0) { $0 + .pi * $1.radius * $1.radius }
    let scale = (Self.fill * .pi * Self.wall * Self.wall * 0.84 / max(area, 1e-9)).squareRoot()
    for index in all.indices { all[index].radius *= scale }
    // The deepest pieces draw first, so nearer ones sit on top of them.
    pieces = all.sorted { $0.depth > $1.depth }
  }

  /// How busy the sound is each second: the change in its overall loudness, smoothed
  /// over a few seconds and averaging 1, added up into a clock.
  static func motionClock(for state: KaleidoscopePlayer.RenderState) -> [Double] {
    let length = state.motion.map(\.count).max() ?? 0
    guard length > 1 else { return [] }
    let loudness = (0..<length).map { second -> Double in
      var power = 0.0
      for (tone, track) in state.motion.enumerated() where !track.isEmpty {
        let level = Double(state.levels[tone * 2] + state.levels[tone * 2 + 1])
        let gain = Double(track[second % track.count])
        power += level * level * gain * gain
      }
      return 10 * log10(max(power, 1e-12))
    }
    let change = (0..<length).map { abs(loudness[($0 + 1) % length] - loudness[$0]) }
    let smooth = (0..<length).map { second in
      (-4...4).reduce(0.0) { $0 + change[(second + $1 + length) % length] } / 9
    }
    let mean = max(smooth.reduce(0, +) / Double(length), 1e-9)
    var clock = [0.0]
    for second in 0..<length {
      // Quiet stretches still creep along at a quarter speed.
      clock.append(clock[second] + 0.25 + 0.75 * pow(smooth[second] / mean, 1.5))
    }
    return clock
  }

  /// How far the sound has turned the chamber by a playback position, in radians.
  /// It turns faster while the sound is moving and slower while it holds still.
  func turn(at seconds: Double) -> Double {
    let length = motionClock.count - 1
    guard length > 0 else { return seconds * turnRate }
    let speed = state.motionSpeed.first ?? 1
    let position = max(seconds, 0) * speed
    let loops = (position / Double(length)).rounded(.down)
    let within = position - loops * Double(length)
    let index = min(Int(within), length - 1)
    let partial =
      motionClock[index] + (motionClock[index + 1] - motionClock[index]) * (within - Double(index))
    return (loops * motionClock[length] + partial) / max(speed, 1e-6) * turnRate
  }

  /// One piece of glass, placed in the drawing of the wedge the mirrors look into.
  struct Sprite {
    var center: CGPoint
    var radius: Double
    var rotation: Double
    var color: [Float]
    var glow: Double
    var kind: Double
    var seed: Double
    var depth: Double
    var presence: Double
  }

  /// The pieces that show in the mirrors' wedge, laid out for drawing. `apex` is where
  /// the wedge's point sits in the drawing, `axis` is the way it runs, `span` is the
  /// points in one unit of the chamber and `reach` is how far along the wedge to draw.
  func sprites(
    at seconds: Double, in tumbler: KaleidoscopeTumbler, apex: CGPoint, axis: CGVector,
    span: Double, reach: Double
  ) -> [Sprite] {
    // The mirrors meet at the chamber's middle and look straight down into the pile.
    let slope = tan(.pi / Double(folds) / 2)
    var sprites = [Sprite]()
    for (index, piece) in pieces.enumerated() {
      let body = tumbler.bodies[index]
      let along = body.y
      let across = body.x
      let margin = piece.radius * 1.9
      guard along > -margin, along * span < reach + margin * span,
        abs(across) < max(along, 0) * slope + margin
      else { continue }
      var power = 0.0
      for offset in [-1.5, 0, 1.5] {
        let gain = KaleidoscopePlayer.envelopeGain(
          state: state, partial: piece.tone, absoluteFrame: seconds + offset)
        power += gain * gain / 3
      }
      sprites.append(
        Sprite(
          center: CGPoint(
            x: apex.x + (axis.dx * along - axis.dy * across) * span,
            y: apex.y + (axis.dy * along + axis.dx * across) * span),
          radius: piece.radius * span,
          rotation: body.angle,
          color: piece.color,
          glow: min(max(0.55 + 10 * log10(max(power, 1e-6)) / 16, 0), 1),
          kind: piece.kind, seed: piece.seed, depth: piece.depth, presence: piece.presence))
    }
    return sprites
  }
}

/// Loose glass in a round, oil-filled chamber. Gravity pulls the pieces
/// into a pile, the turning chamber carries them up one side, and they slide and
/// tumble back down over each other.
nonisolated final class KaleidoscopeTumbler {
  struct Body {
    var x: Double
    var y: Double
    var lastX: Double
    var lastY: Double
    var angle: Double
    var radius: Double
  }

  private(set) var bodies: [Body]
  let wall: Double
  private var lastDate: Date?
  private var lastTurn = 0.0
  private var turnSpeed = 0.0

  // Which pieces are near which, rebuilt every step so only neighbors are compared.
  private let largestRadius: Double
  private var cellOf: [Int]
  private var cellStart = [Int]()
  private var cellPieces: [Int]
  private var neighborStart: [Int]
  private var neighbors = [Int]()

  /// Downward pull, in spans a second squared.
  static let gravity = 7.0
  /// How strongly the oil slows a piece. Higher is thicker oil.
  static let drag = 0.9
  /// How firmly touching surfaces hold each other, from 0 (ice) to 1 (locked).
  static let grip = 0.22
  /// The fastest turn the glass follows, in radians a second.
  static let fastestTurn = 2.4
  /// How quickly the glass picks up a change in turning. Lower is gentler.
  static let pickup = 9.0
  /// Pieces overlap a little, the way glass stacks in a chamber with some depth.
  static let overlap = 0.9
  static let stepSec = 1.0 / 60

  init(chamber: KaleidoscopeChamber) {
    let wall = KaleidoscopeChamber.wall
    self.wall = wall
    var seed = chamber.seed | 1
    // Laid in rows across the lower half, already nearly at rest, then left to settle.
    let largest = chamber.pieces.map(\.radius).max() ?? 0.1
    let spacing = largest * 1.15
    var slots = [(Double, Double)]()
    var row = 0
    while slots.count < chamber.pieces.count, row < 400 {
      let y = wall - spacing * (0.6 + Double(row))
      let half = (max(wall * wall - y * y, 0)).squareRoot() - spacing * 0.6
      var x = -half + (row.isMultiple(of: 2) ? 0 : spacing * 0.5)
      while x <= half {
        slots.append((x, y))
        x += spacing
      }
      row += 1
    }
    // Shuffled, so sizes and colors are mixed through the pile.
    for index in slots.indices.reversed() where index > 0 {
      slots.swapAt(index, Int(KaleidoscopePlayer.nextUnit(&seed) * Double(index + 1)))
    }
    bodies = chamber.pieces.enumerated().map { index, piece in
      let slot = index < slots.count ? slots[index] : (0.0, 0.0)
      return Body(
        x: slot.0, y: slot.1, lastX: slot.0, lastY: slot.1,
        angle: KaleidoscopePlayer.nextUnit(&seed) * 2 * .pi, radius: piece.radius * Self.overlap)
    }
    largestRadius = bodies.map(\.radius).max() ?? 0.1
    cellOf = [Int](repeating: 0, count: bodies.count)
    cellPieces = [Int](repeating: 0, count: bodies.count)
    neighborStart = [Int](repeating: 0, count: bodies.count + 1)
    for _ in 0..<90 { step(turnSpeed: 0) }
  }

  /// Builds and settles the glass off the main thread, so the screen never waits on it.
  @concurrent static func settled(chamber: KaleidoscopeChamber) async -> sending KaleidoscopeTumbler
  {
    KaleidoscopeTumbler(chamber: chamber)
  }

  /// Steps the glass up to a moment, given how far the chamber has turned by then.
  func advance(to date: Date, turn: Double) {
    defer {
      lastDate = date
      lastTurn = turn
    }
    guard let lastDate else { return }
    let elapsed = min(date.timeIntervalSince(lastDate), 0.1)
    guard elapsed > 0 else { return }
    // A flick can't whip the glass around: its turning eases toward the hand's, up
    // to a top speed.
    let asked = min(max((turn - lastTurn) / elapsed, -Self.fastestTurn), Self.fastestTurn)
    turnSpeed += (asked - turnSpeed) * (1 - exp(-elapsed * Self.pickup))
    let steps = max(1, Int((elapsed / Self.stepSec).rounded()))
    for _ in 0..<steps { step(turnSpeed: turnSpeed) }
  }

  func step(turnSpeed: Double) {
    let dt = Self.stepSec
    let hold = exp(-dt * Self.drag)
    // The turning chamber carries the whole pile around with it. Gravity then pulls
    // every piece back down, so the pile keeps slumping and folding over itself.
    let cosine = cos(turnSpeed * dt)
    let sine = sin(turnSpeed * dt)
    for index in bodies.indices {
      var body = bodies[index]
      (body.x, body.y) = (body.x * cosine - body.y * sine, body.x * sine + body.y * cosine)
      (body.lastX, body.lastY) = (
        body.lastX * cosine - body.lastY * sine, body.lastX * sine + body.lastY * cosine
      )
      var speedX = (body.x - body.lastX) / dt * hold
      var speedY = (body.y - body.lastY) / dt * hold
      // A piece that has all but stopped comes to rest, so a settled pile lies still.
      if speedX * speedX + speedY * speedY < 0.0009 {
        speedX *= 0.5
        speedY *= 0.5
      }
      speedY += Self.gravity * dt
      body.lastX = body.x
      body.lastY = body.y
      body.x += speedX * dt
      body.y += speedY * dt
      // A piece turns with the chamber, and rolls a little as it slides sideways.
      body.angle += turnSpeed * dt + speedX * dt / body.radius * 0.25
      bodies[index] = body
    }
    findNeighbors()
    for _ in 0..<4 {
      for first in bodies.indices {
        for slot in neighborStart[first]..<neighborStart[first + 1] {
          let second = neighbors[slot]
          let dx = bodies[second].x - bodies[first].x
          let dy = bodies[second].y - bodies[first].y
          let reach = bodies[first].radius + bodies[second].radius
          let distanceSquared = dx * dx + dy * dy
          guard distanceSquared < reach * reach, distanceSquared > 1e-12 else { continue }
          let distance = distanceSquared.squareRoot()
          let push = (reach - distance) / distance
          // The heavier piece gives way less.
          let firstMass = bodies[first].radius * bodies[first].radius
          let secondMass = bodies[second].radius * bodies[second].radius
          let share = secondMass / (firstMass + secondMass)
          bodies[first].x -= dx * push * share
          bodies[first].y -= dy * push * share
          bodies[second].x += dx * push * (1 - share)
          bodies[second].y += dy * push * (1 - share)
          // Touching pieces grip each other, which slows their sliding past one another.
          let nx = dx / distance
          let ny = dy / distance
          let slipX =
            (bodies[second].x - bodies[second].lastX) - (bodies[first].x - bodies[first].lastX)
          let slipY =
            (bodies[second].y - bodies[second].lastY) - (bodies[first].y - bodies[first].lastY)
          let along = slipX * nx + slipY * ny
          let sideX = (slipX - along * nx) * Self.grip
          let sideY = (slipY - along * ny) * Self.grip
          bodies[first].x += sideX * share
          bodies[first].y += sideY * share
          bodies[second].x -= sideX * (1 - share)
          bodies[second].y -= sideY * (1 - share)
        }
      }
      for index in bodies.indices {
        let limit = wall - bodies[index].radius
        let reach = (bodies[index].x * bodies[index].x + bodies[index].y * bodies[index].y)
          .squareRoot()
        if reach > limit, reach > 1e-9 {
          let nx = bodies[index].x / reach
          let ny = bodies[index].y / reach
          var x = nx * limit
          var y = ny * limit
          // The wall grips the pieces resting on it, so it carries them as it turns.
          let slipX = x - bodies[index].lastX
          let slipY = y - bodies[index].lastY
          let along = slipX * nx + slipY * ny
          x -= (slipX - along * nx) * Self.grip
          y -= (slipY - along * ny) * Self.grip
          bodies[index].x = x
          bodies[index].y = y
        }
      }
    }
  }

  /// Lists, for every piece, the later pieces close enough to touch it this step. The
  /// margin is a whole piece wide, which keeps the result the same as comparing them all.
  private func findNeighbors() {
    let margin = largestRadius
    let cell = largestRadius * 2 + margin
    let columns = Int((2 * wall / cell).rounded(.up)) + 2
    let count = bodies.count
    if cellStart.count != columns * columns + 2 {
      cellStart = [Int](repeating: 0, count: columns * columns + 2)
    }
    for index in cellStart.indices { cellStart[index] = 0 }
    for index in 0..<count {
      let column = min(max(Int((bodies[index].x + wall) / cell) + 1, 0), columns - 1)
      let row = min(max(Int((bodies[index].y + wall) / cell) + 1, 0), columns - 1)
      cellOf[index] = row * columns + column
      cellStart[cellOf[index] + 2] += 1
    }
    // After this, a cell's pieces sit between cellStart[cell + 1] and cellStart[cell + 2].
    for index in 1..<cellStart.count { cellStart[index] += cellStart[index - 1] }
    for index in 0..<count {
      cellPieces[cellStart[cellOf[index] + 1]] = index
      cellStart[cellOf[index] + 1] += 1
    }
    neighbors.removeAll(keepingCapacity: true)
    for first in 0..<count {
      neighborStart[first] = neighbors.count
      let row = cellOf[first] / columns
      let column = cellOf[first] % columns
      for nearRow in max(row - 1, 0)...min(row + 1, columns - 1) {
        for nearColumn in max(column - 1, 0)...min(column + 1, columns - 1) {
          let near = nearRow * columns + nearColumn
          for slot in cellStart[near]..<cellStart[near + 1] {
            let second = cellPieces[slot]
            guard second > first else { continue }
            let dx = bodies[second].x - bodies[first].x
            let dy = bodies[second].y - bodies[first].y
            let reach = bodies[first].radius + bodies[second].radius + margin
            if dx * dx + dy * dy < reach * reach { neighbors.append(second) }
          }
        }
      }
      // Lowest first, the order the pieces would be met comparing them all.
      neighbors[neighborStart[first]...].sort()
    }
    neighborStart[count] = neighbors.count
  }
}
