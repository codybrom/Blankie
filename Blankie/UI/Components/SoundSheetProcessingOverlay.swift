//
//  SoundSheetProcessingOverlay.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

struct SoundSheetProcessingOverlay: View {
  let progressMessage: LocalizedStringKey
  /// Completion from 0 to 1. When set, a determinate bar shows from the start in
  /// place of the spinner.
  var fraction: Double?
  /// Shows a Cancel button when set.
  var onCancel: (() -> Void)?

  var body: some View {
    ZStack {
      Color.black.opacity(0.3)
        .ignoresSafeArea()
        .accessibilityHidden(true)

      VStack(spacing: 16) {
        if let fraction {
          ProgressView(value: fraction) {
            Text(progressMessage)
              .font(.headline)
          } currentValueLabel: {
            Text(fraction, format: .percent.precision(.fractionLength(0)))
              .monospacedDigit()
          }
          .frame(width: 240)
        } else {
          VStack(spacing: 12) {
            ProgressView()
              .scaleEffect(1.5)
            Text(progressMessage)
              .font(.headline)
          }
          // Read the spinner + status message as a single VoiceOver announcement.
          .accessibilityElement(children: .combine)
        }

        if let onCancel {
          Button("Cancel", role: .cancel, action: onCancel)
        }
      }
      .padding(24)
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
