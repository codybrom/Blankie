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
      soundNameView

      attributionView
    }
    .font(.aboutCaption)
    .padding(.vertical, 4)
    // One navigable container per credit, named for the sound, so VoiceOver reads it
    // as a unit ("Rain, group") with the source and license links inside.
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(credit.localizedName))
  }

  private var soundNameView: some View {
    HStack(spacing: 4) {
      Text(credit.localizedName)
        .fontWeight(.bold)
        // The container is labeled with the sound name and doesn't need re-announced
        .accessibilityHidden(true)

      Text(verbatim: " — ")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      if let soundUrl = credit.soundUrl {
        // `.tint` follows the app accent, but `Color.accentColor` ignores the .tint
        // environment on macOS.
        Link(credit.soundName, destination: soundUrl)
          .foregroundStyle(.tint)
          .underline()
          .handCursor()
          .accessibilityHint(Text("Opens the sound source"))
      } else {
        Text(credit.soundName)
          .foregroundStyle(.secondary)
      }
    }
  }

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
          .foregroundStyle(.tint)
          .handCursor()
      }
    }
  }
}
