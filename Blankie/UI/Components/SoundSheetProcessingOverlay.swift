//
//  SoundSheetProcessingOverlay.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

struct SoundSheetProcessingOverlay: View {
  let progressMessage: LocalizedStringKey

  var body: some View {
    ZStack {
      Color.black.opacity(0.3)
        .ignoresSafeArea()
        .accessibilityHidden(true)

      VStack(spacing: 12) {
        ProgressView()
          .scaleEffect(1.5)
        Text(progressMessage)
          .font(.headline)
      }
      .padding(24)
      // Read the spinner + status message as a single VoiceOver announcement.
      .accessibilityElement(children: .combine)
      .background(
        Group {
          #if os(macOS)
            Color(NSColor.windowBackgroundColor)
          #else
            Color(UIColor.systemBackground)
          #endif
        }
      )
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .shadow(radius: 20)
    }
  }
}
