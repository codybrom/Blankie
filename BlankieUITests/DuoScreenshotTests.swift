//
//  DuoScreenshotTests.swift
//  BlankieUITests
//
//  Created by Cody Bromley on 10/25/26.
//

#if os(iOS)
  import XCTest

  /// Plays a preset and captures every display, for iPhone Duo screenshots. Set the
  /// pose first, then run with TEST_RUNNER_PRESET set to the preset's name.
  @MainActor final class DuoScreenshotTests: XCTestCase {
    func testPlayPresetAndCaptureDisplays() throws {
      let name = try XCTUnwrap(
        ProcessInfo.processInfo.environment["PRESET"].flatMap { $0.isEmpty ? nil : $0 },
        "Set TEST_RUNNER_PRESET to the preset to capture.")
      let app = XCUIApplication()
      app.activate()

      // The Library sits behind a back button on every layout but the shut phone's root.
      let row = app.buttons[name].firstMatch
      if !row.waitForExistence(timeout: 3) || !row.isHittable {
        let back = ["Library", "BackButton", "Back"].map { app.buttons[$0].firstMatch }
        back.first { $0.exists && $0.isHittable }?.tap()
      }
      let list = app.collectionViews.firstMatch
      for _ in 0..<5 where !row.exists || !row.isHittable {
        list.swipeUp(velocity: .slow)
      }
      XCTAssertTrue(row.waitForExistence(timeout: 5), "No preset named \(name)")
      row.tap()

      let play = app.buttons["Play"].firstMatch
      if play.waitForExistence(timeout: 3), play.isHittable { play.tap() }
      XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 5))

      for (index, screen) in XCUIScreen.screens.enumerated() {
        let attachment = XCTAttachment(screenshot: screen.screenshot())
        attachment.name = "\(name) – display \(index)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }
#endif
