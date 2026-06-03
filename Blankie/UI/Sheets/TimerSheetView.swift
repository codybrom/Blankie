//
//  TimerSheetView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/7/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct TimerSheetView: View {
    @StateObject private var timerManager = TimerManager.shared
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss

    /// The accent driving the action buttons. Mirrors the precedence used by
    /// the Now Playing sheet so the timer's button matches the surrounding UI.
    /// `themingPreset` is nil during solo / Quick Mix, so those use the app
    /// accent (the timer is reachable from solo mode's bottom toolbar).
    private var accentColor: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    var body: some View {
      NavigationStack {
        VStack(spacing: 20) {
          if timerManager.isTimerActive {
            activeTimerContent
          } else {
            timerSelectionContent
          }
        }
        .navigationTitle("Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          // The primary action ("Start Timer" / "Cancel Timer") lives in the
          // content; this toolbar button only dismisses, so it's a leading
          // Close rather than a trailing "Done".
          ToolbarItem(placement: .topBarLeading) {
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark")
            }
            .tint(Color.primary)
            .accessibilityLabel(Text("Close"))
          }
        }
      }
    }

    private var activeTimerContent: some View {
      VStack(spacing: 20) {
        Spacer()

        Text("Pausing in")
          .font(.headline)
          .foregroundColor(.secondary)

        Text(timerManager.formatRemainingTime())
          .font(.system(size: 48, weight: .light, design: .rounded))
          .monospacedDigit()

        if let endTime = timerManager.getEndTime() {
          Text("at \(endTime.formatted(date: .omitted, time: .shortened))")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        // Time adjustment controls
        VStack(spacing: 8) {
          Text("Add More Time")
            .font(.caption)
            .foregroundColor(.secondary)

          HStack(spacing: 16) {
            timeAdjustmentButton("1 min", minutes: 1)
            timeAdjustmentButton("5 min", minutes: 5)
          }
        }
        .padding(.horizontal)

        Spacer()

        Button(action: {
          timerManager.stopTimer()
        }) {
          Label("Cancel Timer", systemImage: "xmark.circle.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(accentColor)
        .padding(.horizontal)

        Spacer()
      }
    }

    private func timeAdjustmentButton(_ label: String, minutes: Int) -> some View {
      return Button(action: {
        timerManager.addTime(minutes: minutes)
      }) {
        Text(label)
          .font(.system(.body, design: .rounded))
          .fontWeight(.medium)
          .foregroundColor(.primary)
          .frame(minWidth: 64)
          .frame(height: 36)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.green.opacity(0.15))
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color.green.opacity(0.3), lineWidth: 1)
              )
          )
      }
    }

    private var timerSelectionContent: some View {
      VStack(spacing: 30) {
        HStack(spacing: 30) {
          VStack {
            Text("Hours")
              .font(.caption)
              .foregroundColor(.secondary)
            Picker("Hours", selection: $timerManager.selectedHours) {
              ForEach(0...23, id: \.self) { hour in
                Text(verbatim: "\(hour)")
                  .tag(hour)
              }
            }
            .pickerStyle(.wheel)
            .frame(width: 80, height: 150)
            .labelsHidden()
          }

          Text(verbatim: ":")
            .font(.largeTitle)
            .padding(.top, 20)

          VStack {
            Text("Minutes")
              .font(.caption)
              .foregroundColor(.secondary)
            Picker("Minutes", selection: $timerManager.selectedMinutes) {
              ForEach(0...59, id: \.self) { minute in
                Text(verbatim: String(format: "%02d", minute))
                  .tag(minute)
              }
            }
            .pickerStyle(.wheel)
            .frame(width: 80, height: 150)
            .labelsHidden()
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
          Label("Start Timer", systemImage: "timer")
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(accentColor)
        .padding(.horizontal)
        .disabled(timerManager.selectedHours == 0 && timerManager.selectedMinutes == 0)

        Text("Blankie will pause when timer expires")
          .font(.body)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
    }
  }
#endif
