//
//  ErrorReporter.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

import SwiftUI
import os

class ErrorReporter: ObservableObject {
  static let shared = ErrorReporter()
  @Published var lastError: Error?

  func report(_ error: Error) {
    DispatchQueue.main.async {
      self.lastError = error
      #if DEBUG
        Logger.app.error("Error reported: \(error.localizedDescription, privacy: .public)")
      #endif
    }
  }
}
