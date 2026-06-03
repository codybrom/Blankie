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
    .font(.caption)
    .padding(.vertical, 4)
    // Make each credit one navigable container named for the sound, so VoiceOver
    // announces it as a unit ("Rain, group") with the source/license links as
    // items inside rather than loose siblings that bleed into the next credit.
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(credit.name))
  }

  // Extracted view for the sound name line
  private var soundNameView: some View {
    HStack(spacing: 4) {
      Text(credit.name)
        .fontWeight(.bold)
        // The container is labeled with the sound name and doesn't need re-announced
        .accessibilityHidden(true)

      Text(verbatim: " — ")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      if let soundUrl = credit.soundUrl {
        // With link case
        Link(credit.soundName, destination: soundUrl)
          .foregroundColor(.accentColor)
          .underline()
          .handCursor()
          .accessibilityHint(Text("Opens the sound source"))
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
      // Group "By <author>" into a single VoiceOver element
      HStack(spacing: 4) {
        Text("By")
          .foregroundStyle(.secondary)
        Text(credit.author)
      }
      .accessibilityElement(children: .combine)

      if let licenseUrl = credit.license.url {
        Text(verbatim: "•").foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Link(credit.license.linkText, destination: licenseUrl)
          .help(licenseUrl.absoluteString)
          .foregroundColor(.accentColor)
          .handCursor()
      }
    }
  }
}
