//
//  SoundCredit.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

// Sound credit model
struct SoundCredit {
  let name: String  // English title, the lookup key for a sound's credit
  let fileName: String
  let soundName: String  // Original work title
  let author: String  // Author/creator
  let license: License  // License type
  let soundUrl: URL?  // Link to original work

  /// The sound's name as the app shows it.
  var localizedName: String {
    Sound.builtInName(fileName: fileName, englishTitle: name)
  }

  var attributionText: String {
    var text = "\"\(soundName)\""
    text += " by \(author)"
    return text
  }
}
