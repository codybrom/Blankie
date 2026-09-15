//
//  IntentError.swift
//  Blankie
//
//  Created by Cody Bromley on 6/30/26.
//

import Foundation

/// Errors surfaced by Blankie's App Intents (Siri/Shortcuts). Presented to the
/// user via `IntentDialog`/system error UI, so messages are user-facing.
enum BlankieIntentError: LocalizedError {
  case presetNotFound
  case soundNotFound

  var errorDescription: String? {
    switch self {
    case .presetNotFound:
      return String(localized: "That preset couldn't be found.", comment: "App Intent error")
    case .soundNotFound:
      return String(localized: "That sound couldn't be found.", comment: "App Intent error")
    }
  }
}
