//
//  ProgressBorderView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

struct ProgressBorderView: View {
  let iconSize: CGFloat
  let borderWidth: CGFloat
  let sound: Sound  // Changed to pass sound object for live updates
  let color: Color

  var body: some View {
    // Use TimelineView for smooth 30 FPS progress updates
    // TimelineView automatically optimizes for battery life and system performance
    TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
      Circle()
        .trim(from: 0, to: getCurrentProgress())
        .stroke(
          color,
          style: StrokeStyle(
            lineWidth: borderWidth,
            lineCap: .round
          )
        )
        .frame(width: iconSize, height: iconSize)
        .rotationEffect(.degrees(-90))
        .padding(borderWidth)  // Add padding before drawingGroup to prevent clipping
        .drawingGroup()  // Composite to offscreen buffer for better performance
        .padding(-borderWidth)  // Remove padding after to maintain original size
    }
    .accessibilityHidden(true)
  }

  private func getCurrentProgress() -> Double {
    guard let player = sound.player, player.duration > 0 else {
      return 0.0
    }
    return player.currentTime / player.duration
  }
}
