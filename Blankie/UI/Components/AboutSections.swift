//
//  AboutSections.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

struct DeveloperSection: View {
  var body: some View {
    VStack(spacing: 4) {
      Text("Developed By", comment: "Developed by label")
        .font(.system(size: 13, weight: .bold))

      VStack(spacing: 8) {
        Text(verbatim: "Cody Bromley")
          .font(.system(size: 13))

        HStack(spacing: 8) {

          Link(destination: URL(string: "https://www.codybrom.com")!) {
            Text("Website", comment: "Website link label")
          }
          .foregroundColor(.accentColor)
          .handCursor()

          Text(verbatim: "•")
            .foregroundStyle(.secondary)

          Link(destination: URL(string: "https://github.com/codybrom")!) {
            Text(verbatim: "GitHub")
          }
          .foregroundColor(.accentColor)
          .handCursor()

        }
        .foregroundColor(.accentColor)
        .font(.system(size: 12))
      }

    }
    .frame(maxWidth: .infinity)
  }
}

struct ContributorSection: View {
  let contributors: [String]
  var body: some View {
    VStack(spacing: 8) {  // Standardized spacing
      Text("Contributors", comment: "Contributors section title")
        .font(.system(size: 13, weight: .bold))
        .padding(.bottom, 4)  // Add some space between title and content

      HStack(spacing: 0) {
        ForEach(contributors.indices, id: \.self) { index in
          Text(contributors[index])
            .font(.system(size: 13))

          if index < contributors.count - 1 {
            Text(verbatim: ", ")
              .font(.system(size: 13))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 4)  // Consistent bottom padding
  }
}

struct TranslatorSection: View {
  let translators: [String: [String]]
  var body: some View {
    VStack(spacing: 8) {  // Standardized spacing
      Text("Translations", comment: "Translations section title")
        .font(.system(size: 13, weight: .bold))
        .padding(.bottom, 4)  // Same spacing after title

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
                    .font(.system(size: 12, weight: .medium))
                    .italic()
                    .foregroundStyle(.secondary)

                  Text(translatorList.joined(separator: ", "))
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 150, alignment: .center)
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
              .font(.system(size: 12, weight: .medium))
              .italic()
              .foregroundStyle(.secondary)

            Text(translatorList.joined(separator: ", "))
              .font(.system(size: 13))
              .multilineTextAlignment(.center)
              .lineLimit(3)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(width: 150, alignment: .center)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 4)  // Consistent bottom padding
  }
}

struct InspirationSection: View {
  var body: some View {
    let projectURL = URL(string: "https://github.com/rafaelmardojai/blanket")!

    return Link(destination: projectURL) {
      Text(LocalizedStringKey("Inspired by Blanket by Rafael Mardojai CM"))
        .font(.system(size: 12))
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
      .font(.system(size: 12))
      Text(
        verbatim:
          "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:"
      )
      .font(.system(size: 12))
      Text(
        verbatim:
          "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."
      )
      .font(.system(size: 12))
      Text(
        verbatim:
          "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
      )
      .font(.system(size: 12))
      Link(
        "Learn more about the MIT License",
        destination: URL(string: "https://opensource.org/licenses/MIT")!
      )
      .foregroundColor(.accentColor)
      .font(.system(size: 12))
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
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      } else {
        ForEach(dependencies, id: \.name) { dependency in
          Text(
            verbatim:
              "\(dependency.name) by \(dependency.author), licensed under the \(dependency.license)."
          )
          .font(.system(size: 12))
        }
      }
    }
    .onAppear {
      loadDependencies()
    }
  }

  private func loadDependencies() {
    guard let url = Bundle.main.url(forResource: "credits", withExtension: "json") else {
      debugLog("Unable to find credits.json in bundle")
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let credits = try decoder.decode(Credits.self, from: data)
      self.dependencies = credits.dependencies ?? []
    } catch {
      debugLog("Error loading dependencies: \(error)")
    }
  }
}
