//
//  AnimatedWaveformView.swift
//  Blankie
//
//  Animated waveform that cycles through low/mid/high states
//

import SwiftUI

struct AnimatedWaveformView: View {
  let size: CGFloat
  let color: Color

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.5, paused: false)) { timeline in
      let elapsed = timeline.date.timeIntervalSinceReferenceDate
      let cyclePosition = Int(elapsed / 0.5) % 4

      Image(systemName: waveformSymbol(for: cyclePosition))
        .font(.system(size: size))
        .foregroundColor(color)
        .shadow(radius: 4)
        .contentTransition(.symbolEffect(.replace))
    }
    .animation(.smooth(duration: 0.4), value: Date.now)
    .accessibilityHidden(true)
  }

  private func waveformSymbol(for position: Int) -> String {
    switch position {
    case 0: return "waveform.low"
    case 1: return "waveform.mid"
    case 2: return "waveform"
    default: return "waveform.mid"
    }
  }
}

#Preview {
  ZStack {
    Color.black
    AnimatedWaveformView(size: 40, color: .white)
  }
}
