//
//  KaleidoscopeBackdrop.swift
//  Blankie
//
//  Created by Cody Bromley on 11/10/26.
//

import SwiftUI

/// A glass kaleidoscope drawn from a Kaleidoscope's recipe, with each
/// piece glowing as its tone swells. The glass in the mirrors' wedge is drawn once,
/// then a second pass folds it around the center.
struct KaleidoscopeBackdrop: View {
  let sound: KaleidoscopeSound
  var isPlaying: Bool
  /// Where the artwork would sit, in global coordinates.
  var artworkFrame: CGRect?
  /// Off when the controls are put away, so the whole picture shows at full strength.
  var dimsForControls = true
  /// The turn a finger has given the chamber. It is read fresh on every frame, so
  /// dragging never has to redraw the player around it.
  var touch = TouchBox()
  /// True while a finger is turning the glass or it is still coasting, so the
  /// picture keeps moving even when the sound is paused.
  var isTouched = false

  final class TouchBox {
    var touch = Touch()
    /// The drag's last reading, and its running speed in radians a second.
    var lastSample: (angle: Double, time: Date)?
    var speed = 0.0

    /// Turns the chamber with a drag around `center`. True when this reading starts a turn.
    func drag(to location: CGPoint, about center: CGPoint, at time: Date) -> Bool {
      let x = location.x - center.x
      let y = location.y - center.y
      // Too near the center, the angle swings wildly.
      guard x * x + y * y > 30 * 30 else {
        lastSample = nil
        return false
      }
      let angle = atan2(y, x)
      guard let last = lastSample else {
        touch = .init(base: touch.angle(at: time))
        lastSample = (angle, time)
        return true
      }
      var delta = angle - last.angle
      if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
      let elapsed = max(time.timeIntervalSince(last.time), 1.0 / 240)
      touch.base -= delta
      speed = speed * 0.6 + (-delta / elapsed) * 0.4
      lastSample = (angle, time)
      return false
    }

    /// Lets go, leaving the chamber to coast. Returns the moment of release.
    func release() -> Date {
      touch.velocity = min(max(speed, -2), 2)
      let released = Date.now
      touch.releasedAt = released
      lastSample = nil
      speed = 0
      return released
    }

    /// True once the coast from `released` has died away with no new turn since.
    func hasSettled(since released: Date) -> Bool {
      touch.releasedAt == released && lastSample == nil
    }
  }

  /// A turn of the chamber by hand: where the finger left it, and how it coasts on.
  struct Touch {
    var base = 0.0
    /// Radians a second at the moment of letting go.
    var velocity = 0.0
    var releasedAt = Date.distantPast

    /// The coast eases out over a couple of seconds.
    static let coastSec = 1.3

    func angle(at date: Date) -> Double {
      let elapsed = max(date.timeIntervalSince(releasedAt), 0)
      return base + velocity * Self.coastSec * (1 - exp(-elapsed / Self.coastSec))
    }
  }

  /// The loose glass, kept between frames. Nothing is drawn until it has settled.
  @State private var glass: Glass?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private struct Glass {
    let chamber: KaleidoscopeChamber
    let tumbler: KaleidoscopeTumbler
  }

  var body: some View {
    ZStack {
      Color.black
      if let glass {
        picture(chamber: glass.chamber, tumbler: glass.tumbler)
      }
    }
    .task {
      guard glass == nil else { return }
      let chamber = KaleidoscopeChamber(recipe: sound.recipe)
      glass = Glass(chamber: chamber, tumbler: await KaleidoscopeTumbler.settled(chamber: chamber))
    }
  }

  private func picture(chamber: KaleidoscopeChamber, tumbler: KaleidoscopeTumbler) -> some View {
    GeometryReader { proxy in
      let size = proxy.size
      let frame = proxy.frame(in: .global)
      let art =
        artworkFrame?.offsetBy(dx: -frame.minX, dy: -frame.minY)
        ?? CGRect(
          x: size.width * 0.08, y: size.height * 0.17, width: size.width * 0.84,
          height: size.width * 0.84)
      let center = CGPoint(x: art.midX, y: art.midY)
      // One span is most of the screen's short side, upright or turned.
      let span = min(size.width, size.height) * 0.92
      // The wedge is drawn from the middle of a short edge, running the long way.
      let sideways = size.width > size.height
      let apex = sideways ? CGPoint(x: 0, y: size.height / 2) : CGPoint(x: size.width / 2, y: 0)
      let axis = sideways ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1)
      let reach =
        [
          CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height),
          CGPoint(x: size.width, y: size.height),
        ].map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0

      // Low Power Mode halves the frame rate. Off screen, nothing is drawn at all.
      let frameSec = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 15.0 : 1.0 / 30.0
      TimelineView(
        .animation(
          minimumInterval: frameSec,
          paused: scenePhase != .active || (!isPlaying && !isTouched))
      ) { context in
        let seconds = sound.playbackPosition
        // The sound turns the chamber, and so does a finger. The glass does the rest.
        // With Reduce Motion on, only a finger turns it. The glass still glows.
        let soundTurn = reduceMotion ? 0 : chamber.turn(at: seconds)
        let _ = tumbler.advance(
          to: context.date, turn: soundTurn - touch.touch.angle(at: context.date))
        let sprites = chamber.sprites(
          at: seconds, in: tumbler, apex: apex, axis: axis, span: span, reach: reach)
        Canvas { canvas, _ in
          for sprite in sprites {
            let reach = sprite.radius * 1.9
            let box = Path(
              CGRect(
                x: sprite.center.x - reach, y: sprite.center.y - reach, width: reach * 2,
                height: reach * 2))
            canvas.fill(
              box,
              with: .shader(
                ShaderLibrary.glassShadow(
                  .float2(sprite.center), .float(sprite.radius), .float(sprite.rotation),
                  .float(sprite.kind), .float(sprite.seed), .float(sprite.presence))))
            canvas.fill(
              box,
              with: .shader(
                ShaderLibrary.glassPiece(
                  .float2(sprite.center), .float(sprite.radius), .float(sprite.rotation),
                  .float3(sprite.color[0], sprite.color[1], sprite.color[2]),
                  .float(sprite.glow), .float(sprite.kind), .float(sprite.seed),
                  .float(sprite.depth), .float(span), .float(sprite.presence))))
          }
        }
        .layerEffect(
          ShaderLibrary.kaleidoscopeFold(
            .float2(center), .float(Float(chamber.folds)), .float2(apex),
            .float2(axis.dx, axis.dy), .float(span), .float(Float(KaleidoscopeChamber.wall)),
            .float3(chamber.wash[0], chamber.wash[1], chamber.wash[2])),
          maxSampleOffset: CGSize(width: size.width, height: size.height))

      }
      // Dims behind the title and controls for contrast, without hiding the glass.
      // They sit below the artwork on an upright phone and beside it on a turned one.
      .overlay {
        let edge = sideways ? art.maxX / max(size.width, 1) : art.maxY / max(size.height, 1)
        let fadeStart = min(edge, 0.95)
        LinearGradient(
          stops: [
            .init(color: .black.opacity(0), location: max(fadeStart - 0.10, 0)),
            .init(color: .black.opacity(0.55), location: min(fadeStart + 0.08, 1)),
            .init(color: .black.opacity(0.62), location: 1),
          ],
          startPoint: sideways ? .leading : .top, endPoint: sideways ? .trailing : .bottom
        )
        .opacity(dimsForControls ? 1 : 0)
      }
    }
    .background(.black)
  }
}
