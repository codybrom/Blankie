//
//  Bundle+TestFlight.swift
//  Blankie
//
//  Created by Cody Bromley on 5/24/26.
//

import Foundation
import StoreKit

extension Bundle {
  /// Whether beta-tester-only UI (such as the "Get Credited as a Tester" link
  /// in Settings) should be shown.
  ///
  /// Returns `true` for local DEBUG builds and for TestFlight installs, and
  /// `false` for App Store releases — so beta-only UI auto-hides once the app
  /// ships, with no manual cleanup required.
  ///
  /// TestFlight detection uses StoreKit's `AppTransaction`, which reports the
  /// signing environment: TestFlight installs are signed in `.sandbox`, App
  /// Store installs in `.production`. (This replaces the deprecated
  /// `appStoreReceiptURL` / `sandboxReceipt` check.) Verification isn't
  /// security-critical here — this only toggles cosmetic beta UI — so the
  /// payload is read from both the verified and unverified cases.
  ///
  /// `AppTransaction.shared` is `async` and may require network connectivity;
  /// it throws when no transaction is available. On any throw (offline first
  /// launch, Simulator, StoreKit-testing/`.xcode`, etc.) the gate returns
  /// `false`, so App Store users never see beta UI. A TestFlight install
  /// opened offline may briefly read `false` until a launch that can reach
  /// the App Store — acceptable for a cosmetic gate.
  var isTestFlightOrDebug: Bool {
    get async {
      #if DEBUG
        return true
      #else
        do {
          let result = try await AppTransaction.shared
          let appTransaction: AppTransaction
          switch result {
          case .verified(let transaction), .unverified(let transaction, _):
            appTransaction = transaction
          }
          return appTransaction.environment == .sandbox
        } catch {
          return false
        }
      #endif
    }
  }
}
