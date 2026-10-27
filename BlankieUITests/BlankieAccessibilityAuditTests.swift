//
//  BlankieAccessibilityAuditTests.swift
//  BlankieUITests
//
//  Created by Cody Bromley on 6/8/26.
//
//  Runs `performAccessibilityAudit` over the live UI and fails on any issue not deliberately
//  ignored. VoiceOver speech and Switch Control have no XCTest API, so they're tested by hand.
//

import XCTest

final class BlankieAccessibilityAuditTests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
    executionTimeAllowance = 120
  }

  /// Audits the main mixer screen, the densest surface.
  @MainActor func testMixerAccessibilityAudit() throws {
    let app = XCUIApplication()
    // ScreenshotMode activates sounds so the audit sees a populated grid.
    app.launchArguments = ["-UITestingResetDefaults", "YES", "-ScreenshotMode", "YES"]
    app.launch()
    sleep(2)  // Let the grid, glass, and Now Playing bar settle.

    // Single sound and preset state survive the UI-test reset (app-group store), so select the
    // default preset, which also exits single sound.
    let defaultPreset = app.buttons["All Blankie Sounds"].firstMatch
    if defaultPreset.waitForExistence(timeout: 5) {
      #if os(macOS)
        defaultPreset.click()
      #else
        defaultPreset.tap()
      #endif
      sleep(1)
    }

    // `performAccessibilityAudit` is main-actor isolated yet logs a non-failing "should not be
    // called on the main thread" advisory. That's a framework issue with nothing to fix here.
    try app.performAccessibilityAudit { self.shouldIgnoreAuditIssue($0) }
  }

  /// Whether an audit issue is a documented framework/system false positive to
  /// ignore, or a real finding that should fail the test.
  @MainActor private func shouldIgnoreAuditIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
    // Layout containers (NavigationSplitView groups, the grid's `Other`, window chrome) trip the
    // description and parent/child checks. Their labeled descendants carry the meaning.
    let isContainer =
      issue.element?.elementType == .group || issue.element?.elementType == .other
    if isContainer,
      issue.auditType == .sufficientElementDescription || issue.auditType == .parentChild
    {
      return true
    }

    // The macOS Touch Bar is a system element, present even without the hardware.
    if issue.element?.elementType == .touchBar {
      return true
    }

    // A SwiftUI `Menu` exposes show-menu (which VoiceOver operates), but `.action` only
    // recognizes press. Framework false positive.
    if issue.auditType == .action, issue.element?.elementType == .menuButton {
      return true
    }

    // A native slider's knob is an AppKit ValueIndicator that SwiftUI can't label. VoiceOver
    // reads the labeled slider. Framework false positive.
    #if os(macOS)
      if issue.auditType == .sufficientElementDescription,
        issue.element?.elementType == .valueIndicator
      {
        return true
      }
    #endif

    // Real finding: log and fail.
    print("⚠️ [A11y audit] \(issue.auditType): \(issue.compactDescription)")
    print("   element: \(issue.element?.debugDescription ?? "nil")")
    return false
  }
}
