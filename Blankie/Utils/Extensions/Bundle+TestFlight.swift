//
//  Bundle+TestFlight.swift
//  Blankie
//
//  Created by Cody Bromley on 5/24/26.
//

import Foundation
import StoreKit

extension Bundle {
  private static let probeAttempts = 3

  /// Whether beta-tester-only UI (such as the "Get Credited as a Tester" link
  /// in Settings) should be shown.
  ///
  /// Returns `true` for local DEBUG builds and for TestFlight installs, and
  /// `false` for App Store releases (and whenever the environment can't be
  /// determined) — so beta-only UI auto-hides once the app ships, with no
  /// manual cleanup required.
  ///
  /// Detection uses StoreKit's `AppTransaction`, whose `environment` reports
  /// the signing environment: TestFlight installs are signed in `.sandbox`,
  /// App Store installs in `.production`. This is the only viable signal here —
  /// the deprecated `appStoreReceiptURL` / `sandboxReceipt` check is `nil` in
  /// the iOS sandbox for an app without in-app purchases, and a build-time flag
  /// can't tell a TestFlight build apart from the same binary promoted to the
  /// App Store. Verification isn't security-critical (cosmetic UI only), so the
  /// payload is read from both the verified and unverified cases.
  ///
  /// `AppTransaction.shared`'s first call after a cold launch can throw
  /// `StoreKitError.unknown` ("Unable to Complete Request") before StoreKit has
  /// the signed transaction cached, so the probe retries briefly; if every
  /// attempt still fails it returns `false` (App Store users must never see
  /// beta UI). It never calls `AppTransaction.refresh()` — that's the
  /// documented recovery, but it shows an App Store sign-in prompt and so must
  /// only run on an explicit user action, not from this automatic gate.
  var isTestFlightOrDebug: Bool {
    get async {
      #if DEBUG
        return true
      #else
        for attempt in 1...Bundle.probeAttempts {
          do {
            let result = try await AppTransaction.shared
            let transaction: AppTransaction
            switch result {
            case .verified(let value), .unverified(let value, _):
              transaction = value
            }
            return transaction.environment == .sandbox
          } catch {
            if attempt < Bundle.probeAttempts {
              try? await Task.sleep(for: .seconds(2))
            }
          }
        }
        return false
      #endif
    }
  }
}
