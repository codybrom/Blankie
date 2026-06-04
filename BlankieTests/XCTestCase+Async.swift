//
//  XCTestCase+Async.swift
//  BlankieTests
//
//  Created by Cody Bromley on 1/10/25.
//

import XCTest

extension XCTestCase {
  func waitForAsync(timeout: TimeInterval = 1.0, completion: @escaping () async -> Void) async {
    let expectation = expectation(description: "Async operation")

    Task {
      await completion()
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: timeout)
  }
}
