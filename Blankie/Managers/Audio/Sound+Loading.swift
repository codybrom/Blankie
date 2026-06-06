//
//  Sound+Loading.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import AVFoundation
import os

extension Sound {

  func getSoundURL() -> URL? {
    if isCustom, let customURL = fileURL {
      // Verify the custom sound file actually exists
      if FileManager.default.fileExists(atPath: customURL.path) {
        Logger.sounds.debug("Sound: Loading custom sound from: \(customURL.path)")
        return customURL
      } else {
        Logger.sounds.debug("Sound: Custom sound file not found at path: \(customURL.path)")
        return nil
      }
    } else {
      Logger.sounds.debug("Sound: Loading built-in sound from bundle")
      return Bundle.main.url(forResource: fileName, withExtension: fileExtension)
    }
  }

}
