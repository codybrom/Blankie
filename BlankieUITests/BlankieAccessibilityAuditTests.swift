//
//  BlankieAccessibilityAuditTests.swift
//  BlankieUITests
//
//  Created by Cody Bromley on 6/8/26.
//
//  Automated accessibility backstop (#57): `performAccessibilityAudit` runs the
//  Accessibility Inspector's checks over the live UI and fails on any issue not
//  deliberately ignored. Also the empirical guard for the label (#55) and Liquid
//  Glass contrast (#56) work. VoiceOver speech and Switch Control aren't
//  automatable (no XCTest API) — those stay in notes/a11y-test-plan.md.
//

import XCTest

final class BlankieAccessibilityAuditTests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
    executionTimeAllowance = 120
  }

  /// Audits the main mixer screen — the densest, highest-traffic surface.
  func testMixerAccessibilityAudit() throws {
    let app = XCUIApplication()
    // ScreenshotMode activates sounds so the audit sees a populated grid.
    app.launchArguments = ["-UITestingResetDefaults", "YES", "-ScreenshotMode", "YES"]
    app.launch()
    sleep(2)  // Let the grid, glass, and Now Playing bar settle.

    // Pin to a deterministic surface: solo/preset state survives the UI-test
    // reset (it lives in the shared app-group store), so force the default
    // preset, which also exits solo mode.
    let defaultPreset = app.buttons["All Blankie Sounds"].firstMatch
    if defaultPreset.waitForExistence(timeout: 5) {
      #if os(macOS)
        defaultPreset.click()
      #else
        defaultPreset.tap()
      #endif
      sleep(1)
    }

    // `performAccessibilityAudit` is @MainActor-isolated, so it must run on the
    // main thread — then emits a non-failing "should not be called on the main
    // thread" advisory. An Apple framework contradiction: not the Main Thread
    // Checker (disabling it had no effect), and off-main is impossible. Worth a
    // feedback report; nothing to fix here.
    try app.performAccessibilityAudit { self.shouldIgnoreAuditIssue($0) }
  }

  /// Whether an audit issue is a documented framework/system false positive to
  /// ignore, or a real finding that should fail the test.
  private func shouldIgnoreAuditIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
    // Structural containers (NavigationSplitView's groups, the grid's `Other`,
    // window-chrome groups) are layout wrappers, not controls — they trip the
    // no-description and parent/child checks while their labeled descendants
    // carry the meaning. Real controls never surface as a bare container.
    let isContainer =
      issue.element?.elementType == .group || issue.element?.elementType == .other
    if isContainer,
      issue.auditType == .sufficientElementDescription || issue.auditType == .parentChild
    {
      return true
    }

    // The macOS Touch Bar is a system element (present with no items / no
    // hardware); not app content and can't be described.
    if issue.element?.elementType == .touchBar {
      return true
    }

    // A SwiftUI `Menu` is a pull-down button: its action is show-menu (which
    // VoiceOver operates), but `.action` only recognizes a press action. The
    // menu is HIG-correct and VoiceOver-verified operable; the alternatives that
    // expose a press action are worse. Framework false positive.
    if issue.auditType == .action, issue.element?.elementType == .menuButton {
      return true
    }

    // Real finding: log and fail.
    print("⚠️ [A11y audit] \(issue.auditType): \(issue.compactDescription)")
    print("   element: \(issue.element?.debugDescription ?? "nil")")
    return false
  }
}
