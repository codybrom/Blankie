//
//  ErrorReporter.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

import SwiftUI

class ErrorReporter: ObservableObject {
  static let shared = ErrorReporter()
  @Published var lastError: Error?

  func report(_ error: Error) {
    DispatchQueue.main.async {
      self.lastError = error
      #if DEBUG
        logError("Error reported: \(error.localizedDescription)")
      #endif
    }
  }
}
