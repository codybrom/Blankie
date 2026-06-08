//
//  DockPresenceManager.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/26.
//

#if os(macOS)
  import AppKit
  import Combine

  /// Hides/shows the Dock icon by switching `NSApplication`'s activation policy
  /// (`.accessory` hides it, `.regular` shows it) from the menu bar settings and
  /// window visibility. Only hides while the menu bar icon is shown, so a closed
  /// window is always reachable. (Activation policy is finicky — verify on a real
  /// macOS 26 build.)
  final class DockPresenceManager {
    static let shared = DockPresenceManager()

    private var cancellables = Set<AnyCancellable>()

    /// Begin observing the settings + window state. Call once after launch.
    func start() {
      let settings = GlobalSettings.shared
      Publishers.CombineLatest4(
        settings.$showMenuBarIcon,
        settings.$menuBarOnlyMode,
        settings.$hideDockWhenWindowClosed,
        WindowObserver.shared.$hasVisibleWindow
      )
      // Switching policy must happen on the main thread; coalesce bursts.
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.apply() }
      .store(in: &cancellables)

      // Keep the Dock pause badge correct even when the main window is closed:
      // its in-window owner (ContentView) is gone, but the menu bar popover can
      // still drive playback. This observer is always alive.
      let audio = AudioManager.shared
      Publishers.CombineLatest3(
        audio.$isGloballyPlaying,
        audio.$hasSelectedSounds,
        settings.$showDockBadgeWhenPaused
      )
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateDockBadge() }
      .store(in: &cancellables)
    }

    /// Badge the Dock icon whenever the app is silent — paused, or "playing"
    /// with nothing selected (matching the in-window status banner).
    private func updateDockBadge() {
      let audio = AudioManager.shared
      let silent = !audio.isGloballyPlaying || !audio.hasSelectedSounds
      NSApp.dockTile.badgeLabel =
        (silent && GlobalSettings.shared.showDockBadgeWhenPaused) ? "⏸" : nil
    }

    private func apply() {
      let settings = GlobalSettings.shared
      let hasWindow = WindowObserver.shared.hasVisibleWindow

      // Never hide the Dock without the menu bar icon — a closed window would be
      // unreachable.
      let shouldHide =
        settings.showMenuBarIcon
        && (settings.menuBarOnlyMode
          || (settings.hideDockWhenWindowClosed && !hasWindow))

      let desired: NSApplication.ActivationPolicy = shouldHide ? .accessory : .regular
      guard NSApp.activationPolicy() != desired else { return }

      // Switching to .accessory orders the app's open windows out. Capture any
      // genuinely-visible window so the switch never strands it off-screen with
      // no Dock icon to reopen it — trust the live window list, not `hasWindow`,
      // which can be stale during the launch race. A window that's actually
      // closing is already !isVisible here, so this never resurrects it.
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
