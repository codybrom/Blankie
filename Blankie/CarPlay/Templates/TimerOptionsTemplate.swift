//
// TimerOptionsTemplate.swift
// Blankie
//
// Created by Cody Bromley on 6/9/26.
//

import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  /// Sleep-timer picker pushed from the CarPlay Now Playing screen. Offers a few
  /// fixed durations (and a cancel option while a timer is running) so a driver
  /// can set "pause in N minutes" without leaving CarPlay.
  enum TimerOptionsTemplate {
    /// Durations offered on CarPlay, in minutes.
    static let durationsInMinutes = [5, 10, 15, 20, 30, 60]

    @MainActor
    static func createTemplate() -> CPListTemplate {
      let template = CPListTemplate(title: String(localized: "Timer"), sections: [])
      updateTemplate(template)
      return template
    }

    @MainActor
    static func updateTemplate(_ template: CPListTemplate) {
      var sections: [CPListSection] = []

      let timerManager = TimerManager.shared
      if timerManager.isTimerActive {
        sections.append(activeTimerSection(timerManager))
      } else {
        // Explain what picking a duration does before any timer is running.
        let info = CPListItem(
          text: String(localized: "Blankie will pause at the end of the timer"), detailText: nil)
        info.isEnabled = false
        sections.append(CPListSection(items: [info]))
      }

      let durationItems = durationsInMinutes.map { createDurationItem($0) }
      sections.append(
        CPListSection(
          items: durationItems,
          header: timerManager.isTimerActive ? String(localized: "Restart Timer") : nil,
          sectionIndexTitle: nil
        )
      )

      template.updateSections(sections)
    }

    private static func activeTimerSection(_ timerManager: TimerManager) -> CPListSection {
      // Show the fixed stop instant ("pauses at 10:36 AM"), not a live countdown:
      // this list is a static snapshot and a frozen MM:SS reads as a stuck timer.
      let status = CPListItem(text: pauseAtText(timerManager), detailText: nil)
      status.isEnabled = false

      let cancel = CPListItem(text: String(localized: "Cancel Timer"), detailText: nil)
      cancel.setImage(tinted("xmark.circle.fill"))
      cancel.handler = { _, completion in
        Task { @MainActor in
          TimerManager.shared.stopTimer()
          CarPlayInterfaceController.shared.popTimerOptions()
          completion()
        }
      }

      return CPListSection(items: [status, cancel])
    }

    private static func createDurationItem(_ minutes: Int) -> CPListItem {
      let item = CPListItem(text: durationLabel(minutes), detailText: nil)
      item.setImage(tinted("timer"))
      item.handler = { _, completion in
        Task { @MainActor in
          TimerManager.shared.startTimer(duration: TimeInterval(minutes * 60))
          CarPlayInterfaceController.shared.popTimerOptions()
          completion()
        }
      }
      return item
    }

    /// Accent-tinted glyph rasterized into a bitmap. `CPListItem.setImage`
    /// renders a plain SF Symbol black, so we bake the color into opaque pixels.
    private static func tinted(_ systemName: String) -> UIImage? {
      let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
      guard
        let symbol = UIImage(systemName: systemName, withConfiguration: config)?
          .withTintColor(.carPlayIconTint, renderingMode: .alwaysOriginal)
      else { return nil }

      let canvas = CGSize(width: 40, height: 40)
      let renderer = UIGraphicsImageRenderer(size: canvas)
      return renderer.image { _ in
        let target = symbol.size
        symbol.draw(
          at: CGPoint(x: (canvas.width - target.width) / 2, y: (canvas.height - target.height) / 2))
      }
    }

    /// "Blankie pauses at 10:36 AM", using the timer's fixed stop instant.
    private static func pauseAtText(_ timerManager: TimerManager) -> String {
      guard let endTime = timerManager.getEndTime() else { return String(localized: "Timer running") }
      let formatter = DateFormatter()
      formatter.timeStyle = .short
      return String(localized: "Blankie pauses at \(formatter.string(from: endTime))")
    }

    private static func durationLabel(_ minutes: Int) -> String {
      if minutes >= 60 {
        let hours = minutes / 60
        return hours == 1 ? String(localized: "1 hour") : String(localized: "\(hours) hours")
      }
      return String(localized: "\(minutes) minutes")
    }
  }

#endif
