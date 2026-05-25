//
//  Bundle+TestFlight.swift
//  Blankie
//
//  Created by Cody Bromley on 5/24/26.
//

import Foundation

extension Bundle {
  /// Whether beta-tester-only UI (such as the "Get Credited as a Tester" link
  /// in Settings) should be shown.
  ///
  /// Returns `true` for local DEBUG builds and for TestFlight installs, and
  /// `false` for App Store releases — so beta-only UI auto-hides once the app
  /// ships, with no manual cleanup required.
  ///
  /// TestFlight detection relies on the App Store receipt: TestFlight installs
  /// carry a `sandboxReceipt`. Note this also returns `true` in the Simulator,
  /// which is acceptable for beta-tester UI.
  ///
  /// `appStoreReceiptURL` is soft-deprecated (iOS 18 / macOS 15) but still
  /// functional; the sanctioned replacement, StoreKit's `AppTransaction`, is
  /// async and not worth the complexity for a gate that disappears at release.
  /// Revisit if the property is ever fully removed.
  var isTestFlightOrDebug: Bool {
    #if DEBUG
      return true
    #else
      return appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    #endif
  }
}
