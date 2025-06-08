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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationView {
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
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
              dismiss()
            }
          }
        }
      }
    }

    private var activeTimerContent: some View {
      VStack(spacing: 20) {
        Spacer()

        Text("Stopping in")
          .font(.headline)
          .foregroundColor(.secondary)

        Text(timerManager.formatRemainingTime())
          .font(.system(size: 48, weight: .light, design: .rounded))
          .monospacedDigit()

        if let endTime = timerManager.getEndTime() {
          Text("at \(endTime, formatter: timeFormatter)")
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
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.tint)
            .cornerRadius(10)
        }
        .padding(.horizontal)

        Spacer()
      }
    }

    private var timeFormatter: DateFormatter {
      let formatter = DateFormatter()
      formatter.timeStyle = .short
      return formatter
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
          }
        }) {
          Label("Start Timer", systemImage: "timer")
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.tint)
            .cornerRadius(10)
        }
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
