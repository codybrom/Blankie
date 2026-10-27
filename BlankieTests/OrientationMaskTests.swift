//
//  OrientationMaskTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/24/26.
//
//  The legacy portrait lock is a phone-sized preference: it holds unless the
//  window is regular both ways, so it never pins an open iPhone Duo or an iPad.
//

#if os(iOS)
  import Testing
  import UIKit

  @testable import Blankie

  @MainActor @Suite struct OrientationMaskTests {
    @Test func lockedCompactIsPortrait() {
      #expect(
        IOSAppDelegate.orientationMask(
          lockPortrait: true, horizontalSizeClass: .compact, verticalSizeClass: .regular)
          == .portrait)
    }

    /// A Plus or Pro Max held sideways is regular width but compact height.
    @Test func lockedLargePhoneSidewaysIsPortrait() {
      #expect(
        IOSAppDelegate.orientationMask(
          lockPortrait: true, horizontalSizeClass: .regular, verticalSizeClass: .compact)
          == .portrait)
    }

    /// Early in launch the traits can be unspecified; the lock still holds.
    @Test func lockedUnspecifiedIsPortrait() {
      #expect(
        IOSAppDelegate.orientationMask(
          lockPortrait: true, horizontalSizeClass: .unspecified, verticalSizeClass: .unspecified)
          == .portrait)
    }

    @Test func lockedRegularRotates() {
      #expect(
        IOSAppDelegate.orientationMask(
          lockPortrait: true, horizontalSizeClass: .regular, verticalSizeClass: .regular)
          == .all)
    }

    @Test func unlockedAlwaysRotates() {
      #expect(
        IOSAppDelegate.orientationMask(
          lockPortrait: false, horizontalSizeClass: .compact, verticalSizeClass: .regular)
          == .all)
    }
  }
#endif
