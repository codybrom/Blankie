//
//  CreditRow.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

struct CreditRow: View {
  let credit: SoundCredit

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      // First row with name and sound name
      soundNameView

      // Attribution line
      attributionView
    }
    .font(.system(size: 12))
    .padding(.vertical, 4)
  }

  // Extracted view for the sound name line
  private var soundNameView: some View {
    HStack(spacing: 4) {
      Text(credit.name)
        .fontWeight(.bold)

      Text(verbatim: " — ")
        .foregroundStyle(.secondary)

      if let soundUrl = credit.soundUrl {
        // With link case
        Text(credit.soundName)
          .foregroundColor(.accentColor)
          .underline()
          .onTapGesture {
            #if os(macOS)
              NSWorkspace.shared.open(soundUrl)
            #else
              UIApplication.shared.open(soundUrl)
            #endif
          }
          .handCursor()
      } else {
        // Without link case
        Text(credit.soundName)
          .foregroundStyle(.secondary)
      }
    }
  }

  // Extracted view for the attribution line
  private var attributionView: some View {
    HStack(spacing: 4) {
      Text("By")
        .foregroundStyle(.secondary)
      Text(credit.author)

      if let licenseUrl = credit.license.url {
        Text(verbatim: "•").foregroundStyle(.secondary)
        Link(credit.license.linkText, destination: licenseUrl)
          .help(licenseUrl.absoluteString)
          .foregroundColor(.accentColor)
          .handCursor()
      }
    }
  }
}
