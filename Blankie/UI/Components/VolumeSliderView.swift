//
//  VolumeSliderView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

struct VolumeSliderView: View {
  @ObservedObject var sound: Sound
  let width: CGFloat
  let tintColor: Color
  let isEnabled: Bool

  var body: some View {
    Slider(
      value: Binding(
        get: { Double(sound.volume) },
        set: { sound.volume = Float($0) }
      ), in: 0...1
    )
    .frame(width: width)
    .tint(tintColor)
    .disabled(!isEnabled)
    .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
    .accessibilityValue(
      Text(Double(sound.volume).formatted(.percent.precision(.fractionLength(0))))
    )
  }
}
