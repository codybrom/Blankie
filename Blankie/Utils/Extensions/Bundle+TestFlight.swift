//
//  Bundle+TestFlight.swift
//  Blankie
//
//  Created by Cody Bromley on 5/24/26.
//

import Foundation
import StoreKit

#if canImport(MarketplaceKit)
  import MarketplaceKit
#endif

extension Bundle {
  nonisolated private static let probeAttempts = 3

  /// Whether beta-tester-only UI (such as the "Get Credited as a Tester" link
  /// in Settings) should be shown.
  ///
  /// Returns `true` for local DEBUG builds and for TestFlight installs, and
  /// `false` for App Store releases (and whenever the environment can't be
  /// determined) — so beta-only UI auto-hides once the app ships, with no
  /// manual cleanup required.
  ///
  /// The primary signal is MarketplaceKit's `AppDistributor.current` (iOS
  /// 17.4+), which reads the install source from local install metadata —
  /// `.testFlight` vs `.appStore` — with no App Store server round-trip, so it
  /// works where StoreKit's cache is cold or stuck (real TestFlight installs
  /// were throwing `StoreKitError.unknown` and never seeing the beta UI).
  ///
  /// The fallback is StoreKit's `AppTransaction`, whose `environment` reports
  /// the signing environment: TestFlight installs are signed in `.sandbox`,
  /// App Store installs in `.production`. (The deprecated `appStoreReceiptURL`
  /// / `sandboxReceipt` check is `nil` in the iOS sandbox for an app without
  /// in-app purchases, and a build-time flag can't tell a TestFlight build
  /// apart from the same binary promoted to the App Store.) Verification isn't
  /// security-critical (cosmetic UI only), so the payload is read from both
  /// the verified and unverified cases.
  ///
  /// `AppTransaction.shared`'s first call after a cold launch can throw
  /// `StoreKitError.unknown` ("Unable to Complete Request") before StoreKit has
  /// the signed transaction cached, so the probe retries briefly; if every
  /// attempt still fails it returns `false` (App Store users must never see
  /// beta UI). It never calls `AppTransaction.refresh()` — that's the
  /// documented recovery, but it shows an App Store sign-in prompt and so must
  /// only run on an explicit user action, not from this automatic gate.
  // @concurrent so the whole check runs off the main actor: it only calls
  // StoreKit / MarketplaceKit (both nonisolated) and touches no app state, and
  // staying off-main means the non-Sendable `AppDistributor` result is never sent
  // into a main-actor-isolated caller.
  @concurrent func isTestFlightOrDebug() async -> Bool {
    #if DEBUG
      return true
    #else
      #if canImport(MarketplaceKit)
        if let distributor = try? await AppDistributor.current {
          switch distributor {
          case .testFlight:
            return true
          case .appStore:
            return false
          default:
            break  // Unexpected source — fall through to the AppTransaction probe.
          }
        }
      #endif
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
