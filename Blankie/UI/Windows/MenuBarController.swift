//
//  MenuBarController.swift
//  Blankie
//
//  Created by Cody Bromley on 6/10/26.
//

#if os(macOS)
  import AppKit
  import Observation
  import SwiftData
  import SwiftUI

  /// Owns the menu bar status item and its click-through popover directly via
  /// AppKit. SwiftUI's `MenuBarExtra(isInserted:)` won't reliably re-insert a
  /// removed item (it writes a spurious `false` back during re-insertion), so the
  /// "Show in Menu Bar" toggle could never turn the icon back on. Managing the
  /// `NSStatusItem` ourselves gives reliable add/remove plus Cmd-drag-out.
  @MainActor
  final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var visibilityObservation: Task<Void, Never>?
    private var visibilityKVO: NSKeyValueObservation?
    private var closeObserver: NSObjectProtocol?

    init(modelContainer: ModelContainer) {
      popover.behavior = .transient
      popover.contentViewController = NSHostingController(
        rootView: MenuBarContent().modelContainer(modelContainer)
      )

      // The popover content opens windows ("Open Blankie", "Settings…") and asks
      // to close via this notification (NSPopover ignores SwiftUI's dismiss).
      closeObserver = NotificationCenter.default.addObserver(
        forName: .closeMenuBarPopover, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.popover.performClose(nil) }
      }

      apply(visible: GlobalSettings.shared.showMenuBarIcon)
      visibilityObservation = Task { @MainActor [weak self] in
        for await visible in Observations({ GlobalSettings.shared.showMenuBarIcon }) {
          self?.apply(visible: visible)
        }
      }
    }

    deinit {
      visibilityObservation?.cancel()
      if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    /// Add or remove the status item to match the setting.
    private func apply(visible: Bool) {
      if visible {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = .removalAllowed  // Cmd-drag-out removes it
        if let button = item.button {
          let image = NSImage(named: "blankie.symbol")
          image?.isTemplate = true
          button.image = image
          button.action = #selector(togglePopover)
          button.target = self
          button.setAccessibilityLabel(String(localized: "Blankie"))
        }
        // Cmd-dragging the item off the menu bar flips isVisible; mirror that to
        // the setting so the two controls stay in sync and the choice persists.
        visibilityKVO = item.observe(\.isVisible, options: [.new]) { item, _ in
          guard !item.isVisible else { return }
          MainActor.assumeIsolated { GlobalSettings.shared.setShowMenuBarIcon(false) }
        }
        statusItem = item
      } else {
        visibilityKVO = nil
        popover.performClose(nil)
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
      }
    }

    @objc private func togglePopover() {
      guard let button = statusItem?.button else { return }
      if popover.isShown {
        popover.performClose(nil)
      } else {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Key the popover window so its controls (sliders, buttons) take input.
        popover.contentViewController?.view.window?.makeKey()
      }
    }
  }

  extension Notification.Name {
    /// Posted by the menu bar popover content when it wants to close itself.
    static let closeMenuBarPopover = Notification.Name("closeMenuBarPopover")
  }
#endif
