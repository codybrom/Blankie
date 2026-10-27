//
//  BlankieShortcuts.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import AppIntents

/// Preconfigured Siri phrases and App Shortcut tiles for iOS. Apple does not
/// support preconfigured App Shortcuts on macOS, but the individual App Intent
/// actions are still available when building custom shortcuts on the Mac.
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
        "Start \(.applicationName) preset \(\.$preset)",
        "Play the preset \(\.$preset) in \(.applicationName)",
        "Start a preset in \(.applicationName)",
      ],
      shortTitle: "Play a Preset",
      systemImageName: "square.stack.3d.up.fill"
    )
    AppIntents.AppShortcut(
      intent: PlaySoundIntent(),
      phrases: [
        "Play \(\.$sound) sounds in \(.applicationName)",
        "Start \(.applicationName) sound \(\.$sound)",
        "Play the sound \(\.$sound) in \(.applicationName)",
        "Start a sound in \(.applicationName)",
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
