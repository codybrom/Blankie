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

  /// True for DEBUG builds and TestFlight installs, so beta-tester UI shows there.
  /// False for the App Store or when unknown. Checks `AppDistributor.current` where
  /// MarketplaceKit exists, then whether `AppTransaction.shared` reports `.sandbox`,
  /// retrying a cold StoreKit cache. Never calls `refresh()`, which prompts sign-in.
  // @concurrent keeps the non-Sendable `AppDistributor` result off the main actor.
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
            break  // Unknown source: fall through to the AppTransaction probe.
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
