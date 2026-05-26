//
//  PresetLoadingView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

import SwiftUI

struct PresetLoadingView: View {
  var body: some View {
    VStack(spacing: 12) {
      ProgressView()
      Text("Loading Presets...")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}
