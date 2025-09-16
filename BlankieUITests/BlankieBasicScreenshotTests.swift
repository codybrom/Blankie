//
//  BlankieBasicScreenshotTests.swift
//  BlankieUITests
//
//  Created by Cody Bromley on 5/27/25.
//

import XCTest

final class BlankieBasicScreenshotTests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
    executionTimeAllowance = 300  // 5 minutes
  }

  private func findAndTapSoundButton(_ app: XCUIApplication, soundName: String, iconName: String)
    -> Bool
  {
    // Strategy 1: Direct button access by accessibility identifier
    let button1 = app.buttons[iconName]
    if button1.exists && button1.isHittable {
      button1.tap()
      print("✓ Tapped \(soundName) using direct access")
      return true
    }

    // Strategy 2: Find by predicate matching label
    let predicate = NSPredicate(format: "label CONTAINS[c] %@", iconName)
    let button2 = app.buttons.matching(predicate).firstMatch
    if button2.exists && button2.isHittable {
      button2.tap()
      print("✓ Tapped \(soundName) using predicate match")
      return true
    }

    // Strategy 3: Find any button containing the icon elements
    let iconParts = iconName.components(separatedBy: ".")
    for part in iconParts {
      let pred = NSPredicate(format: "label CONTAINS[c] %@", part)
      let button3 = app.buttons.matching(pred).firstMatch
      if button3.exists && button3.isHittable {
        button3.tap()
        print("✓ Tapped \(soundName) using partial match '\(part)'")
        return true
      }
    }

    print("✗ Could not tap \(soundName)")
    return false
  }

  @MainActor
  func testBasicScreenshotsAllLanguages() throws {
    print("\n=== STARTING SCREENSHOT TEST ===\n")
    // Screenshots are saved as XCTest attachments
    // To access them:
    // 1. Open Report Navigator (Cmd+9) in Xcode
    // 2. Find this test run
    // 3. Click on the test
    // 4. Screenshots appear as attachments in the test report
    // 5. Right-click on attachments to save them

    // Languages to test
    let languages = [
      ("en", "English"),
      ("de", "German"),
      ("es", "Spanish"),
      ("fr", "French"),
      ("it", "Italian"),
      ("tr", "Turkish"),
      ("zh-Hans", "Chinese_Simplified"),
    ]

    // No need to configure sounds manually - they'll be set via UserDefaults

    // Now take screenshots in all languages and appearances
    print("\n=== Starting screenshot capture phase ===")

    for isDark in [false, true] {
      let appearanceName = isDark ? "Dark" : "Light"
      print("\n--- Capturing \(appearanceName) mode screenshots ---")

      for (langCode, langName) in languages {
        print("Preparing to capture: \(langName) - \(appearanceName)")

        let app = XCUIApplication()
        app.terminate()

        // Configure launch arguments for screenshots
        app.launchArguments = [
          "-AppleLanguages", "(\(langCode))",
          "-AppleLocale", "\(langCode)",
          "-UITestingResetDefaults", "YES",  // Need to reset to apply appearance
          "-ScreenshotMode", "YES",  // Sets up sounds automatically
        ]

        if isDark {
          app.launchArguments += ["-ForceDarkMode", "YES"]
        }

        // Launch app
        app.launch()

        // Wait for UI to stabilize and window to be configured
        sleep(3)

        // Take screenshot with sounds activated and staggered volumes
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Blankie_\(langName)_\(appearanceName)_WithSounds"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Print what we're capturing
        print("✓ Captured screenshot: \(langName) - \(appearanceName)")

        // Terminate app
        app.terminate()
      }

      print("Completed \(appearanceName) mode screenshots")
    }

    print("\n=== Screenshot capture complete ===\n")
  }
}
