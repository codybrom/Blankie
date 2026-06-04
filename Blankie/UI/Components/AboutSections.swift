//
//  AboutSections.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI
import os

struct DeveloperSection: View {
  var body: some View {
    VStack(spacing: 8) {
      VStack(spacing: 4) {
        Text("Developed By")
          .font(.footnote.weight(.bold))

        Text(verbatim: "Cody Bromley")
          .font(.footnote)
      }
      .accessibilityElement(children: .combine)

      HStack(spacing: 8) {

        Link(destination: URL(string: "https://www.codybrom.com")!) {
          Text("Website")
        }
        .foregroundColor(.accentColor)
        .handCursor()

        Text(verbatim: "•")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        Link(destination: URL(string: "https://github.com/codybrom")!) {
          Text(verbatim: "GitHub")
        }
        .foregroundColor(.accentColor)
        .handCursor()

      }
      .foregroundColor(.accentColor)
      .font(.caption)

    }
    .frame(maxWidth: .infinity)
  }
}

struct ContributorSection: View {
  let contributors: [String]
  var body: some View {
    VStack(spacing: 8) {
      Text("Contributors")
        .font(.footnote.weight(.bold))
        .padding(.bottom, 4)

      HStack(spacing: 0) {
        ForEach(contributors.indices, id: \.self) { index in
          Text(contributors[index])
            .font(.footnote)

          if index < contributors.count - 1 {
            Text(verbatim: ", ")
              .font(.footnote)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .center)
      // Read the contributor list as one phrase ("Hans, Fritz, …") rather than
      // a stutter of name / comma / name VoiceOver stops.
      .accessibilityElement(children: .combine)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 4)
  }
}

struct TranslatorSection: View {
  let translators: [String: [String]]
  var body: some View {
    VStack(spacing: 8) {
      Text("Translations")
        .font(.footnote.weight(.bold))
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
          LazyVGrid(columns: [GridItem(.fixed(150)), GridItem(.fixed(150))], spacing: 20) {
            ForEach(gridLanguages, id: \.self) { language in
              if let translatorList = translators[language], !translatorList.isEmpty {
                VStack(spacing: 4) {
                  Text(language)
                    .font(.caption.weight(.medium))
                    .italic()
                    .foregroundStyle(.secondary)

                  Text(translatorList.joined(separator: ", "))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 150, alignment: .center)
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
              .font(.caption.weight(.medium))
              .italic()
              .foregroundStyle(.secondary)

            Text(translatorList.joined(separator: ", "))
              .font(.footnote)
              .multilineTextAlignment(.center)
              .lineLimit(3)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(width: 150, alignment: .center)
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
        .font(.caption)
        .italic()
        .tint(.accentColor)
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
      .font(.caption)
      Text(
        verbatim:
          "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:"
      )
      .font(.caption)
      Text(
        verbatim:
          "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."
      )
      .font(.caption)
      Text(
        verbatim:
          "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
      )
      .font(.caption)
      Link(
        "Learn more about the MIT License",
        destination: URL(string: "https://opensource.org/licenses/MIT")!
      )
      .foregroundColor(.accentColor)
      .font(.caption)
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
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(dependencies, id: \.name) { dependency in
          Text(
            verbatim:
              "\(dependency.name) by \(dependency.author), licensed under the \(dependency.license)."
          )
          .font(.caption)
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
