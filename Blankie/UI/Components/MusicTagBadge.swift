//
//  MusicTagBadge.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/26.
//

import SwiftUI

/// Music-note badge after a music-tagged sound's name. The circle is an outline when
/// idle and fills with the accent for the active (playing) music sound. A preset
/// plays at most one music sound, so at most one badge is filled.
struct MusicTagBadge: View {
  /// True when this sound holds the preset's music slot and is audible.
  let isActive: Bool
  var accentColor: Color = .accentColor

  private let circleSize: CGFloat = 14

  var body: some View {
    ZStack {
      // A Shape so the fill animates between clear and the accent while the outline
      // fades, which a circle/circle.fill symbol swap can't do.
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
