//
//  TimerView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/29/25.
//

import SwiftUI

struct TimerView: View {
  @StateObject private var timerManager = TimerManager.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme

  private var accentColor: Color {
    #if os(macOS)
      return GlobalSettings.shared.customAccentColor ?? .accentColor
    #else
      return .accentColor
    #endif
  }

  var body: some View {
    VStack(spacing: 16) {
      if timerManager.isTimerActive {
        activeTimerView
      } else {
        timerSelectionView
      }
    }
    .padding()
    .frame(idealWidth: 250, maxWidth: 250, minHeight: 100)
    #if os(macOS)
      .background(Color(NSColor.windowBackgroundColor))
    #endif
  }

  private var activeTimerView: some View {
    VStack(spacing: 16) {
      Image(systemName: "timer")
        .font(.system(size: 48))
        .foregroundStyle(accentColor)

      Text(timerManager.formatRemainingTime())
        .font(.system(size: 32, weight: .light, design: .rounded))
        .monospacedDigit()

      Text("Blankie will pause when timer expires")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(nil)

      Button(action: {
        timerManager.stopTimer()
        dismiss()
      }) {
        Label("Stop Timer", systemImage: "stop.fill")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
      .accentColor(accentColor)
    }
  }

  private var timerSelectionView: some View {
    VStack(spacing: 16) {
      Image(systemName: "timer.circle")
        .font(.system(size: 48))
        .foregroundStyle(accentColor)

      Text("Set Timer")
        .font(.headline)

      Text("Blankie will pause when timer expires")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(nil)

      HStack(spacing: 8) {
        VStack(spacing: 4) {
          Text("Hours")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Picker("Hours", selection: $timerManager.selectedHours) {
            ForEach(0...23, id: \.self) { hour in
              Text(verbatim: "\(hour)")
                .tag(hour)
            }
          }
          .labelsHidden()
          .accentColor(accentColor)
          #if os(macOS)
            .frame(width: 50)
          #else
            .pickerStyle(.wheel)
            .frame(width: 60, height: 80)
          #endif
        }

        VStack(spacing: 4) {
          Text("Minutes")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Picker("Minutes", selection: $timerManager.selectedMinutes) {
            ForEach(0...59, id: \.self) { minute in
              Text(verbatim: String(format: "%02d", minute))
                .tag(minute)
            }
          }
          .labelsHidden()
          .accentColor(accentColor)
          #if os(macOS)
            .frame(width: 50)
          #else
            .pickerStyle(.wheel)
            .frame(width: 60, height: 80)
          #endif
        }
      }

      Button(action: {
        let totalSeconds = TimeInterval(
          timerManager.selectedHours * 3600 + timerManager.selectedMinutes * 60)
        if totalSeconds > 0 {
          timerManager.startTimer(duration: totalSeconds)
          dismiss()
        }
      }) {
        Label("Start Timer", systemImage: "play.fill")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
      .accentColor(accentColor)
      .keyboardShortcut(.defaultAction)
      .disabled(timerManager.selectedHours == 0 && timerManager.selectedMinutes == 0)
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
