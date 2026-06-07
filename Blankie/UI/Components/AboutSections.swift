//
//  AboutSections.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI
import os

// The About content is shared with the compact iOS sheet; macOS resolves text
// styles smaller (footnote/caption are 10pt), so each role steps up there.
extension Font {
  static var aboutHeading: Font {
    #if os(macOS)
      return .body.weight(.bold)
    #else
      return .footnote.weight(.bold)
    #endif
  }
  static var aboutBody: Font {
    #if os(macOS)
      return .body
    #else
      return .footnote
    #endif
  }
  static var aboutCaption: Font {
    #if os(macOS)
      return .callout
    #else
      return .caption
    #endif
  }
}

struct DeveloperSection: View {
  var body: some View {
    HStack(spacing: 4) {
      Text("Developed By")
        .foregroundStyle(.secondary)

      // .tint (not Color.accentColor, which ignores the .tint environment
      // on macOS and stays system blue) so the link follows the app accent.
      Link(destination: URL(string: "https://www.codybrom.com")!) {
        Text(verbatim: "Cody Bromley")
      }
      .foregroundStyle(.tint)
      .handCursor()
      .accessibilityHint(Text("Opens the developer's website"))
    }
    .font(.aboutBody)
    .frame(maxWidth: .infinity)
  }
}

struct ContributorSection: View {
  var title: LocalizedStringKey = "Contributors"
  let contributors: [String]
  var body: some View {
    VStack(spacing: 8) {
      Text(title)
        .font(.aboutHeading)
        .padding(.bottom, 4)

      // One joined Text so long name lists wrap, and VoiceOver reads the
      // list as a single phrase ("Hans, Fritz, …").
      Text(contributors.joined(separator: ", "))
        .font(.aboutBody)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 4)
  }
}

struct TranslatorSection: View {
  let translators: [String: [String]]

  // Wider columns on macOS to match the larger type (and the wider pane).
  #if os(macOS)
    private let columnWidth: CGFloat = 200
  #else
    private let columnWidth: CGFloat = 150
  #endif

  var body: some View {
    VStack(spacing: 8) {
      Text("Translations")
        .font(.aboutHeading)
        .padding(.bottom, 4)

      // Filter out languages without translators
      let translatedLanguages = translators.filter { !$0.value.isEmpty }.keys.sorted()
      let isOddCount = translatedLanguages.count % 2 != 0

      // Split languages for grid and potential last item
      let gridLanguages = isOddCount ? Array(translatedLanguages.dropLast()) : translatedLanguages
      let lastLanguage = isOddCount ? translatedLanguages.last : nil

      VStack(spacing: 20) {
        // Two-column grid for even items
        if !gridLanguages.isEmpty {
          LazyVGrid(
            columns: [GridItem(.fixed(columnWidth)), GridItem(.fixed(columnWidth))], spacing: 20
          ) {
            ForEach(gridLanguages, id: \.self) { language in
              if let translatorList = translators[language], !translatorList.isEmpty {
                VStack(spacing: 4) {
                  Text(language)
                    .font(.aboutCaption.weight(.medium))
                    .italic()
                    .foregroundStyle(.secondary)

                  Text(translatorList.joined(separator: ", "))
                    .font(.aboutBody)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: columnWidth, alignment: .center)
                // Read each language + its translators as one VoiceOver element.
                .accessibilityElement(children: .combine)
              }
            }
          }
          .frame(maxWidth: .infinity)
        }

        // Centered last item if odd count
        if let lastLanguage = lastLanguage,
          let translatorList = translators[lastLanguage], !translatorList.isEmpty
        {
          VStack(spacing: 4) {
            Text(lastLanguage)
              .font(.aboutCaption.weight(.medium))
              .italic()
              .foregroundStyle(.secondary)

            Text(translatorList.joined(separator: ", "))
              .font(.aboutBody)
              .multilineTextAlignment(.center)
              .lineLimit(3)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(width: columnWidth, alignment: .center)
          // Read this language + its translators as one VoiceOver element.
          .accessibilityElement(children: .combine)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 4)
  }
}

struct InspirationSection: View {
  var body: some View {
    let projectURL = URL(string: "https://github.com/rafaelmardojai/blanket")!

    return Link(destination: projectURL) {
      Text(LocalizedStringKey("Inspired by Blanket by Rafael Mardojai CM"))
        .font(.aboutCaption)
        .italic()
        .foregroundStyle(.tint)
        .handCursor()
    }
  }
}

struct SoftwareLicenseSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        verbatim:
          "This application comes with absolutely no warranty. This program is free software: you can redistribute it and/or modify it under the terms of the MIT License.",
      )
      .font(.aboutCaption)
      Text(
        verbatim:
          "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:"
      )
      .font(.aboutCaption)
      Text(
        verbatim:
          "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."
      )
      .font(.aboutCaption)
      Text(
        verbatim:
          "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
      )
      .font(.aboutCaption)
      Link(
        "Learn more about the MIT License",
        destination: URL(string: "https://opensource.org/licenses/MIT")!
      )
      .foregroundStyle(.tint)
      .font(.aboutCaption)
      .handCursor()
    }
  }
}

struct AcknowledgementsSection: View {
  @State private var dependencies: [Dependency] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if dependencies.isEmpty {
        Text("Loading dependencies...")
          .font(.aboutCaption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(dependencies, id: \.name) { dependency in
          Text(
            verbatim:
              "\(dependency.name) by \(dependency.author), licensed under the \(dependency.license)."
          )
          .font(.aboutCaption)
        }
      }
    }
    .onAppear {
      loadDependencies()
    }
  }

  private func loadDependencies() {
    guard let url = Bundle.main.url(forResource: "credits", withExtension: "json") else {
      Logger.ui.debug("Unable to find credits.json in bundle")
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let credits = try decoder.decode(Credits.self, from: data)
      self.dependencies = credits.dependencies ?? []
    } catch {
      Logger.ui.error("Error loading dependencies: \(error, privacy: .public)")
    }
  }
}
