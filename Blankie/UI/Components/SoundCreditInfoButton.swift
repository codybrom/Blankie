//
//  SoundCreditInfoButton.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/26.
//

import SwiftUI

/// Button that pops over a sound's credit (work, author, license).
/// Renders nothing when the sound has no credit to show.
struct SoundCreditInfoButton: View {
  let sound: Sound
  /// Popovers are their own presentation context and don't inherit the
  /// presenting hierarchy's tint, so callers with a preset accent pass it;
  /// nil follows the app-wide accent.
  var accent: Color?

  @State private var showingCredit = false

  var body: some View {
    if let credit = sound.resolvedCredit {
      Button {
        showingCredit = true
      } label: {
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(Text("Sound Credits"))
      .accessibilityHint(Text("Shows credits for this sound"))
      .popover(isPresented: $showingCredit) {
        SoundCreditPopoverContent(credit: credit)
          .tint(accent ?? GlobalSettings.shared.customAccentColor ?? .accentColor)
          #if !os(macOS)
            // Stay a popover on iPhone instead of expanding into a sheet.
            .presentationCompactAdaptation(.popover)
          #endif
      }
    }
  }
}

private struct SoundCreditPopoverContent: View {
  let credit: ResolvedSoundCredit

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // The original work's name leads; the sound's own name is already visible in the row.
      if let workTitle = credit.workTitle {
        linkOrText(workTitle, url: credit.workUrl, hint: Text("Opens the sound source"))
          .font(.headline)
      }

      if credit.author != nil || credit.license != nil {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          if let author = credit.author {
            Text("by \(author)")
              .foregroundStyle(.secondary)
          }
          if credit.author != nil, credit.license != nil {
            Text(verbatim: "·")
              .foregroundStyle(.tertiary)
              .accessibilityHidden(true)
          }
          if let license = credit.license {
            if credit.licenseUrl != nil {
              linkOrText(license.linkText, url: credit.licenseUrl)
            } else {
              Text(license.linkText)
                .foregroundStyle(.secondary)
            }
          }
        }
        .font(.caption)
      }
    }
    // Fixed width keeps popovers a consistent size; text wraps instead of truncating.
    .fixedSize(horizontal: false, vertical: true)
    .padding(12)
    .frame(width: 280, alignment: .leading)
  }

  /// Link with a trailing external-link indicator when a URL is available, plain text otherwise.
  @ViewBuilder
  private func linkOrText(_ text: String, url: URL?, hint: Text? = nil) -> some View {
    if let url {
      Link(destination: url) {
        HStack(spacing: 4) {
          Text(text)
          Image(systemName: "arrow.up.right")
            .font(.caption2)
            .accessibilityHidden(true)
        }
      }
      // .tint, not the default link blue, which ignores the ambient tint
      // on macOS.
      .foregroundStyle(.tint)
      .accessibilityHint(hint ?? Text(verbatim: ""))
    } else {
      Text(text)
    }
  }
}
