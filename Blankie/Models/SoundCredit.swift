//
//  SoundCredit.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

// Sound credit model
struct SoundCredit {
  let name: String  // Display name in app
  let soundName: String  // Original work title
  let author: String  // Author/creator
  let license: License  // License type
  let soundUrl: URL?  // Link to original work

  var attributionText: String {
    var text = "\"\(soundName)\""
    text += " by \(author)"
    return text
  }
}
