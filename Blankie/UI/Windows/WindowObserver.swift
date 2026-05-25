//
//  WindowObserver.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

#if os(macOS)
  import SwiftUI

  class WindowObserver: ObservableObject {
    static let shared = WindowObserver()
    @Published var hasVisibleWindow = false

    private let lastWindowFrameKey = "LastWindowFrame"
    private var debounceTimer: Timer?

    init() {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidBecomeKey),
        name: NSWindow.didBecomeKeyNotification,
        object: nil)

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidClose),
        name: NSWindow.willCloseNotification,
        object: nil)

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidEndResize),
        name: NSWindow.didResizeNotification,
        object: nil)

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidEndMove),
        name: NSWindow.didMoveNotification,
        object: nil)
    }

    @objc private func windowDidEndResize(_ notification: Notification) {
      if let window = notification.object as? NSWindow {
        debouncedSaveWindowFrame(window)
      }
    }

    @objc private func windowDidEndMove(_ notification: Notification) {
      if let window = notification.object as? NSWindow {
        debouncedSaveWindowFrame(window)
      }
    }

    private func debouncedSaveWindowFrame(_ window: NSWindow) {
      debounceTimer?.invalidate()
      debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
        self?.saveWindowFrame(window)
      }
    }

    private func saveWindowFrame(_ window: NSWindow) {
      let frame = window.frame
      let frameDict: [String: Double] = [
        "x": Double(frame.origin.x),
        "y": Double(frame.origin.y),
        "width": Double(frame.size.width),
        "height": Double(frame.size.height),
      ]
      debugLog("🪟 Saving final window frame: \(frameDict)")
      UserDefaults.standard.set(frameDict, forKey: lastWindowFrameKey)
    }

    func getLastWindowFrame() -> NSRect {
      if let frameDict = UserDefaults.standard.dictionary(forKey: lastWindowFrameKey) {
        let frame = NSRect(
          x: (frameDict["x"] as? Double ?? 0),
          y: (frameDict["y"] as? Double ?? 0),
          width: (frameDict["width"] as? Double ?? WindowDefaults.defaultWidth),
          height: (frameDict["height"] as? Double ?? WindowDefaults.defaultHeight)
        )
        debugLog("🪟 Retrieved saved frame: \(frame)")
        return frame
      }
      debugLog("🪟 Using default frame")
      return WindowDefaults.defaultFrame
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
      debugLog("🪟 Window became key")
      DispatchQueue.main.async {
        self.hasVisibleWindow = true
      }
    }

    @objc private func windowDidClose(_ notification: Notification) {
      debugLog("🪟 Window closing")
      DispatchQueue.main.async {
        self.checkVisibleWindows()
      }
    }

    private func checkVisibleWindows() {
      debugLog("🪟 Checking visible windows")
      hasVisibleWindow = NSApp.windows.contains { window in
        window.isVisible && !window.isMiniaturized
      }
    }
  }
#endif
