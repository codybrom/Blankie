//
//  DockPresenceManager.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/26.
//

#if os(macOS)
  import AppKit
  import Combine
  import Observation

  /// Hides or shows the Dock icon by switching the activation policy from the
  /// menu bar settings and window visibility. Activation policy changes need
  /// verifying on a real macOS build.
  final class DockPresenceManager {
    static let shared = DockPresenceManager()

    private var cancellables = Set<AnyCancellable>()
    private var settingsObservation: Task<Void, Never>?
    private var audioObservation: Task<Void, Never>?

    /// Call once after launch.
    func start() {
      // Both handlers are idempotent (apply() returns early when the policy is
      // unchanged), so any settings change runs both.
      settingsObservation = Task { @MainActor [weak self] in
        for await _ in Observations({
          let s = GlobalSettings.shared
          return (
            s.showMenuBarIcon, s.menuBarOnlyMode, s.hideDockWhenWindowClosed,
            s.showDockBadgeWhenPaused
          )
        }) {
          self?.apply()
          self?.updateDockBadge()
        }
      }

      WindowObserver.shared.$hasVisibleWindow
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.apply() }
        .store(in: &cancellables)

      // Owned here so the pause badge stays correct with the main window closed
      // (the menu bar popover can still play).
      audioObservation = Task { @MainActor [weak self] in
        for await _ in Observations({
          let audio = AudioManager.shared
          return (audio.isGloballyPlaying, audio.hasSelectedSounds)
        }) {
          self?.updateDockBadge()
        }
      }
    }

    /// Badges the Dock icon whenever the app is silent: paused, or playing with
    /// nothing selected (matching the in-window status banner).
    private func updateDockBadge() {
      let audio = AudioManager.shared
      let silent = !audio.isGloballyPlaying || !audio.hasSelectedSounds
      NSApp.dockTile.badgeLabel =
        (silent && GlobalSettings.shared.showDockBadgeWhenPaused) ? "⏸" : nil
    }

    private func apply() {
      let settings = GlobalSettings.shared
      let hasWindow = WindowObserver.shared.hasVisibleWindow

      // Never hide the Dock without the menu bar icon, or a closed window would
      // be unreachable.
      let shouldHide =
        settings.showMenuBarIcon
        && (settings.menuBarOnlyMode
          || (settings.hideDockWhenWindowClosed && !hasWindow))

      let desired: NSApplication.ActivationPolicy = shouldHide ? .accessory : .regular
      guard NSApp.activationPolicy() != desired else { return }

      // Switching to .accessory orders open windows out, so capture visible ones
      // to restore. Uses the live window list because `hasWindow` can be stale
      // at launch; a closing window is already !isVisible.
      let openWindows =
        desired == .accessory
        ? NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
        : []

      NSApp.setActivationPolicy(desired)

      switch desired {
      case .regular:
        // Cooperative activation only requests focus; bring the app forward.
        NSApp.activate()
      case .accessory:
        // Restore any window the policy change ordered out.
        for window in openWindows { window.makeKeyAndOrderFront(nil) }
      default:
        break
      }
    }
  }
#endif
