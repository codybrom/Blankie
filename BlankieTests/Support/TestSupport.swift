//
//  TestSupport.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Shared, dependency-free helpers used across the unit-test suites.
//

import Foundation

@testable import Blankie

enum TestSupport {
  /// A fresh, created, UUID-named temporary directory. The caller owns it and
  /// should remove it (use `defer { try? FileManager.default.removeItem(at:) }`).
  static func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("blankie-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}

/// `|a - b| <= tol` — float-tolerant equality for use inside `#expect`.
func isClose(_ a: Double, _ b: Double, tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }
func isClose(_ a: Float, _ b: Float, tol: Float = 1e-4) -> Bool { abs(a - b) <= tol }
