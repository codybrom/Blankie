//
//  SoundSheetCredits.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/26.
//

import SwiftUI

extension CleanSoundSheetForm {
  /// Read-only credit rows (edit mode only); custom sounds add an Edit Credits
  /// row, built-in credits are never editable.
  @ViewBuilder
  var creditsSection: some View {
    if case .edit(let sound) = mode {
      let credit = sound.resolvedCredit
      if credit != nil || sound.isCustom {
        Section(header: Text("Credits")) {
          if let credit {
            creditRows(credit)
          }
          if sound.isCustom {
            editCreditsRow(for: sound, hasCredit: credit != nil)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func creditRows(_ credit: ResolvedSoundCredit) -> some View {
    if let workTitle = credit.workTitle {
      LabeledContent {
        linkOrText(workTitle, url: credit.workUrl, hint: Text("Opens the sound source"))
      } label: {
        Text("Original Work")
      }
    }

    if let author = credit.author {
      LabeledContent("Author", value: author)
    }

    if let license = credit.license {
      LabeledContent {
        linkOrText(license.linkText, url: credit.licenseUrl)
      } label: {
        Text("License")
      }
    }
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
      .foregroundColor(.accentColor)
      .accessibilityHint(hint ?? Text(verbatim: ""))
    } else {
      Text(text)
    }
  }

  @ViewBuilder
  private func editCreditsRow(for sound: Sound, hasCredit: Bool) -> some View {
    let label = hasCredit ? Text("Edit Credits") : Text("Add Credits")
    #if os(macOS)
      // No NavigationStack wraps the macOS sheet, so present the editor as its
      // own sheet rather than a (dead) NavigationLink.
      Button {
        showingCreditsEditor = true
      } label: {
        HStack {
          label
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    #else
      NavigationLink(destination: SoundCreditsEditorView(sound: sound)) {
        label
      }
    #endif
  }
}
