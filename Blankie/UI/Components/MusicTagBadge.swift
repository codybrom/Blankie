//
//  MusicTagBadge.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/26.
//

import SwiftUI

/// Small music-note-in-a-circle badge shown after a music-tagged sound's name.
/// Idle, the circle is a hollow outline (cutout); when this is the active
/// (playing) music sound the circle fills with the accent color. A preset plays
/// at most one music sound at a time, so only one badge is ever filled.
struct MusicTagBadge: View {
  /// True when this is the sound currently holding the preset's music slot and
  /// audible — the "active" music sound.
  let isActive: Bool
  var accentColor: Color = .accentColor

  private let circleSize: CGFloat = 14

  var body: some View {
    ZStack {
      // A Shape (not a circle.fill/circle symbol swap) so the fill color
      // interpolates clear↔accent and the outline fades, giving a smooth
      // transition instead of a hard symbol replace.
      Circle()
        .fill(isActive ? AnyShapeStyle(accentColor) : AnyShapeStyle(.clear))
        .overlay {
          Circle()
            .strokeBorder(.secondary, lineWidth: 1)
            .opacity(isActive ? 0 : 1)
        }
        .frame(width: circleSize, height: circleSize)

      Image(systemName: "music.note")
        .font(.system(size: circleSize * 0.52, weight: .bold))
        .foregroundStyle(isActive ? accentColor.contrastingLabel : Color.secondary)
    }
    .animation(.easeInOut(duration: 0.25), value: isActive)
    .accessibilityHidden(true)
  }
}

#Preview {
  VStack(spacing: 12) {
    HStack {
      Text(verbatim: "Lo-Fi Beats")
      MusicTagBadge(isActive: true, accentColor: .pink)
    }
    HStack {
      Text(verbatim: "Gentle Guitar")
      MusicTagBadge(isActive: false)
    }
  }
  .padding()
}
