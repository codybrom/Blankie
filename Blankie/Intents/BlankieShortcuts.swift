//
//  BlankieShortcuts.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

/// Siri phrases and Shortcuts app tiles. Auto-discovered by the system at
/// build time — no manual registration or Info.plist entry required. Siri
/// phrases/Spotlight tiles only surface on iOS/CarPlay (App Shortcuts aren't
/// supported on macOS); the underlying `AppIntent`s remain available there
/// as building blocks in Shortcuts.app for Mac.
struct BlankieShortcuts: AppShortcutsProvider {
  @AppShortcutsBuilder
  nonisolated static var appShortcuts: [AppIntents.AppShortcut] {
    AppIntents.AppShortcut(
      intent: PlayBlankieIntent(),
      phrases: [
        "Play \(.applicationName)",
        "Resume \(.applicationName)",
      ],
      shortTitle: "Play",
      systemImageName: "play.fill"
    )
    AppIntents.AppShortcut(
      intent: PauseBlankieIntent(),
      phrases: [
        "Pause \(.applicationName)",
        "Stop \(.applicationName)",
      ],
      shortTitle: "Pause",
      systemImageName: "pause.fill"
    )
    AppIntents.AppShortcut(
      intent: PlayPresetIntent(),
      phrases: [
        "Play \(\.$preset) in \(.applicationName)",
        "Play \(\.$preset) on \(.applicationName)",
      ],
      shortTitle: "Play a Preset",
      systemImageName: "square.stack.3d.up.fill"
    )
    AppIntents.AppShortcut(
      intent: PlaySoundIntent(),
      phrases: [
        "Play \(\.$sound) sounds in \(.applicationName)",
        "Play \(\.$sound) in \(.applicationName)",
      ],
      shortTitle: "Play a Sound",
      systemImageName: "waveform"
    )
    AppIntents.AppShortcut(
      intent: StartSleepTimerIntent(),
      phrases: [
        "Start a sleep timer in \(.applicationName)",
        "Set a \(.applicationName) sleep timer",
      ],
      shortTitle: "Sleep Timer",
      systemImageName: "moon.zzz.fill"
    )
    AppIntents.AppShortcut(
      intent: StopSleepTimerIntent(),
      phrases: [
        "Stop the \(.applicationName) sleep timer",
        "Cancel \(.applicationName) sleep timer",
      ],
      shortTitle: "Stop Sleep Timer",
      systemImageName: "moon.zzz"
    )
  }
}
