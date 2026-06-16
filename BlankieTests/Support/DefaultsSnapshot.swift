//
//  DefaultsSnapshot.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  Captures the current values of a set of UserDefaults keys (in BOTH the
//  standard and the shared/app-group suites) and restores them afterward. Tests
//  that exercise real app keys (presets, timer selection, settings) use this so
//  they never corrupt the user's actual data.
//

import Foundation

@testable import Blankie

final class DefaultsSnapshot {
  private let keys: [String]
  private var standard: [String: Any] = [:]
  private var shared: [String: Any] = [:]

  init(_ keys: [String]) {
    self.keys = keys
    for key in keys {
      if let value = UserDefaults.standard.object(forKey: key) { standard[key] = value }
      if let value = UserDefaults.shared.object(forKey: key) { shared[key] = value }
    }
  }

  /// Remove the keys from both suites so a test starts from a clean slate.
  func clear() {
    for key in keys {
      UserDefaults.standard.removeObject(forKey: key)
      UserDefaults.shared.removeObject(forKey: key)
    }
  }

  /// Put the originally captured values back (removing keys that were unset).
  func restore() {
    for key in keys {
      if let value = standard[key] {
        UserDefaults.standard.set(value, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
      if let value = shared[key] {
        UserDefaults.shared.set(value, forKey: key)
      } else {
        UserDefaults.shared.removeObject(forKey: key)
      }
    }
  }
}
