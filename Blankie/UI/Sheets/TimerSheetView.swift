//
//  TimerSheetView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/7/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct TimerSheetView: View {
    @State private var timerManager = TimerManager.shared
    @State private var presetManager = PresetManager.shared
    @State private var globalSettings = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss
    // Scales the large countdown with Dynamic Type while keeping its default size.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownFontSize: CGFloat = 48

    /// The action buttons' accent, using Now Playing's precedence. `themingPreset`
    /// is nil during single sound and Quick Mix, so those use the app accent.
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
          // The primary action ("Start Timer", "Cancel Timer") lives in the content.
          // This toolbar button only dismisses, so it's a leading Close.
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
          .font(.system(size: countdownFontSize, weight: .light, design: .rounded))
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

    private func timeAdjustmentButton(_ label: LocalizedStringKey, minutes: Int) -> some View {
      return Button {
        timerManager.addTime(minutes: minutes)
      } label: {
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
      #if os(iOS)
        .frame(minWidth: 44, minHeight: 44)
      #endif
    }

    private var timerSelectionContent: some View {
      TimerSelectionContent(onStart: { dismiss() })
    }
  }

  /// Hours/minutes wheels and Start Timer, shared by the sheet and the panel.
  struct TimerSelectionContent: View {
    var onStart: () -> Void = {}

    @State private var timerManager = TimerManager.shared
    @State private var presetManager = PresetManager.shared
    @State private var globalSettings = GlobalSettings.shared

    private var accentColor: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    var body: some View {
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
            .accessibilityHidden(true)

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
            onStart()
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

  /// The sleep timer as a panel beside Now Playing on wide screens (Clock's
  /// Timers layout): a ring with the countdown while running, the wheels when
  /// idle. Same actions as the sheet.
  struct TimerPanelView: View {
    @State private var timerManager = TimerManager.shared
    @State private var presetManager = PresetManager.shared
    @State private var globalSettings = GlobalSettings.shared
    @ScaledMetric(relativeTo: .largeTitle) private var countdownFontSize: CGFloat = 64

    private var accentColor: Color {
      presetManager.themingPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }

    private var progress: Double {
      guard timerManager.selectedDuration > 0 else { return 0 }
      return 1 - min(max(timerManager.remainingTime / timerManager.selectedDuration, 0), 1)
    }

    var body: some View {
      if timerManager.isTimerActive {
        running
      } else {
        TimerSelectionContent()
          .frame(maxWidth: 420)
      }
    }

    private var running: some View {
      VStack(spacing: 24) {
        ZStack {
          Circle()
            .stroke(Color.white.opacity(0.15), lineWidth: 10)
          Circle()
            .trim(from: 0, to: 1 - progress)
            .stroke(accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 1), value: progress)
          VStack(spacing: 6) {
            if let endTime = timerManager.getEndTime() {
              Text("Pausing at \(endTime.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Text(timerManager.formatRemainingTime())
              .font(.system(size: countdownFontSize, weight: .light, design: .rounded))
              .monospacedDigit()
              .minimumScaleFactor(0.5)
              .lineLimit(1)
          }
          .padding(28)
          .accessibilityElement(children: .combine)
        }
        // Square, so in a short space (the Duo's flat half) the ring and its
        // countdown shrink to fit.
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 320, maxHeight: 320)

        HStack(spacing: 16) {
          Button {
            timerManager.stopTimer()
          } label: {
            Image(systemName: "xmark")
              .font(.title3.weight(.semibold))
              .frame(width: 56, height: 56)
          }
          .buttonStyle(.glass)
          .buttonBorderShape(.circle)
          .accessibilityLabel(Text("Cancel Timer"))

          Spacer(minLength: 0)

          Button("+1 min") { timerManager.addTime(minutes: 1) }
            .buttonStyle(.glass)
          Button("+5 min") { timerManager.addTime(minutes: 5) }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: 360)
      }
      .padding(.horizontal, 24)
    }
  }
#endif
