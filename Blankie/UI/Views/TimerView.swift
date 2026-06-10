//
//  TimerView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/29/25.
//

import SwiftUI

struct TimerView: View {
  @Bindable private var timerManager = TimerManager.shared
  @ObservedObject private var presetManager = PresetManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @Environment(\.dismiss) private var dismiss
  /// Runs instead of `dismiss()` after start/cancel, so a host like the menu bar
  /// popover can navigate without closing its whole window.
  var onFinish: (() -> Void)?
  // Scales the large countdown with Dynamic Type while keeping its default size.
  @ScaledMetric(relativeTo: .largeTitle) private var countdownFontSize: CGFloat = 44

  /// Theming preset's color wins, else the app accent (solo / Quick Mix).
  private var accentColor: Color {
    presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
  }

  /// Host's `onFinish` if provided, else `dismiss()`.
  private func finish() {
    if let onFinish { onFinish() } else { dismiss() }
  }

  var body: some View {
    VStack(spacing: 20) {
      if timerManager.isTimerActive {
        activeTimerView
      } else {
        timerSelectionView
      }
    }
    .padding(20)
    .frame(idealWidth: 300, maxWidth: 320, minHeight: 120)
    // No opaque background — sit on the host's own glass material.
  }

  private var activeTimerView: some View {
    VStack(spacing: 20) {
      Text("Pausing in")
        .font(.headline)
        .foregroundStyle(.secondary)

      Text(timerManager.formatRemainingTime())
        .font(.system(size: countdownFontSize, weight: .light, design: .rounded))
        .monospacedDigit()

      if let endTime = timerManager.getEndTime() {
        Text("at \(endTime.formatted(date: .omitted, time: .shortened))")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 8) {
        Text("Add More Time")
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack(spacing: 12) {
          addTimeButton("1 min", minutes: 1)
          addTimeButton("5 min", minutes: 5)
        }
      }

      Button {
        timerManager.stopTimer()
        finish()
      } label: {
        Label("Cancel Timer", systemImage: "xmark.circle.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .tint(accentColor)
    }
  }

  private func addTimeButton(_ label: LocalizedStringKey, minutes: Int) -> some View {
    Button {
      timerManager.addTime(minutes: minutes)
    } label: {
      Text(label)
        .font(.system(.body, design: .rounded).weight(.medium))
        .frame(minWidth: 64, minHeight: 32)
    }
    .buttonStyle(.bordered)
    .tint(accentColor)
  }

  private var timerSelectionView: some View {
    VStack(spacing: 20) {
      Image(systemName: "timer")
        .font(.system(size: 44))
        .foregroundStyle(accentColor)
        .accessibilityHidden(true)

      HStack(spacing: 16) {
        labeledPicker("Hours", selection: $timerManager.selectedHours, range: 0...23) {
          Text(verbatim: "\($0)")
        }
        labeledPicker("Minutes", selection: $timerManager.selectedMinutes, range: 0...59) {
          Text(verbatim: String(format: "%02d", $0))
        }
      }

      Button {
        let totalSeconds = TimeInterval(
          timerManager.selectedHours * 3600 + timerManager.selectedMinutes * 60)
        if totalSeconds > 0 {
          timerManager.startTimer(duration: totalSeconds)
          finish()
        }
      } label: {
        Label("Start Timer", systemImage: "play.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .tint(accentColor)
      .keyboardShortcut(.defaultAction)
      .disabled(timerManager.selectedHours == 0 && timerManager.selectedMinutes == 0)

      Text("Blankie will pause when timer expires")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  /// Captioned `.menu` picker (no wheel on macOS), sized to its content.
  private func labeledPicker(
    _ title: LocalizedStringKey, selection: Binding<Int>, range: ClosedRange<Int>,
    label: @escaping (Int) -> Text
  ) -> some View {
    VStack(spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Picker(title, selection: selection) {
        ForEach(Array(range), id: \.self) { label($0).tag($0) }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .tint(accentColor)
      .fixedSize()
    }
  }
}

struct TimerView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      #if os(macOS)
        TimerView()
          .previewDisplayName("macOS Timer")
      #else
        TimerSheetView()
          .previewDisplayName("iOS Timer")
      #endif
    }
  }
}
