//
//  AppSetupRecoveryTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//

import Testing

@testable import Blankie

@Suite struct AppSetupRecoveryActionTests {
  /// The first failure of a launch is treated as transient.
  @Test func firstFailureRetriesInMemory() {
    #expect(AppSetup.recoveryAction(forConsecutiveFailures: 0) == .retryInMemory)
    #expect(AppSetup.recoveryAction(forConsecutiveFailures: 1) == .retryInMemory)
  }

  /// A failure that recurs across launches is treated as corruption.
  @Test func recurringFailureQuarantinesAndRebuilds() {
    #expect(AppSetup.recoveryAction(forConsecutiveFailures: 2) == .quarantineAndRebuild)
    #expect(AppSetup.recoveryAction(forConsecutiveFailures: 7) == .quarantineAndRebuild)
  }
}

/// Serialized: these mutate the shared app-group failure counter.
@Suite(.serialized) struct AppSetupFailureCountTests {
  @Test func countIncrementsAcrossFailuresAndResets() {
    AppSetup.resetStoreFailureCount()
    #expect(AppSetup.incrementStoreFailureCount() == 1)
    #expect(AppSetup.incrementStoreFailureCount() == 2)

    AppSetup.resetStoreFailureCount()
    #expect(AppSetup.incrementStoreFailureCount() == 1)

    AppSetup.resetStoreFailureCount()
  }
}
