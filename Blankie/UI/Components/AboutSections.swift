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

      CenteredFlowLayout(itemSpacing: 8, lineSpacing: 10) {
        // Names and dot separators are interleaved as separate items: a name is
        // fixed so it never breaks mid-word, and the layout drops any separator
        // that lands at the end of a line so dots stay strictly interior.
        ForEach(contributors.indices, id: \.self) { index in
          Text(contributors[index])
            .font(.aboutBody)
            .lineLimit(1)
            .fixedSize()
          if index < contributors.count - 1 {
            Image(systemName: "circle.fill")
              .font(.system(size: 4))
              .foregroundStyle(.tertiary)
              .flowSeparator()
              .accessibilityHidden(true)
          }
        }
      }
      .frame(maxWidth: .infinity)
      // Keep names within the same width as the section dividers (which inset 40).
      .padding(.horizontal, 40)
      // Clip the row-trailing separators the layout parks off-bounds.
      .clipped()
      // Read the whole list as one phrase rather than name-by-name with dots.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(contributors.joined(separator: ", ")))
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 4)
  }
}

/// Marks a flow item as a separator: it glues to the preceding item's line and
/// is dropped when it would land at a line's end, so separators stay interior.
private struct FlowSeparatorKey: LayoutValueKey {
  static let defaultValue = false
}

extension View {
  fileprivate func flowSeparator() -> some View {
    layoutValue(key: FlowSeparatorKey.self, value: true)
  }
}

/// Wrapping flow layout that center-aligns each line. Each subview is placed
/// whole, so a name is never broken across lines. Items tagged `flowSeparator()`
/// never trigger a wrap and are hidden when they fall at the end of a line.
struct CenteredFlowLayout: Layout {
  var itemSpacing: CGFloat = 10
  var lineSpacing: CGFloat = 10

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let separators = subviews.map { $0[FlowSeparatorKey.self] }
    let rows = rows(maxWidth: maxWidth, sizes: sizes, separators: separators)
    let height =
      rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }.reduce(0, +)
      + lineSpacing * CGFloat(max(0, rows.count - 1))
    let widest = rows.map { rowWidth(visible($0, separators: separators), sizes: sizes) }.max() ?? 0
    return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let separators = subviews.map { $0[FlowSeparatorKey.self] }
    let rows = rows(maxWidth: bounds.width, sizes: sizes, separators: separators)
    var y = bounds.minY
    for row in rows {
      let rowHeight = row.map { sizes[$0].height }.max() ?? 0
      let shown = visible(row, separators: separators)
      // Center the visible items (the dropped trailing separator is excluded).
      var x = bounds.minX + max(0, (bounds.width - rowWidth(shown, sizes: sizes)) / 2)
      for itemIndex in row {
        let size = sizes[itemIndex]
        if shown.contains(itemIndex) {
          subviews[itemIndex].place(
            at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
          )
          x += size.width + itemSpacing
        } else {
          // Park the dropped separator off-bounds; the caller clips it away.
          subviews[itemIndex].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY + 1000),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
          )
        }
      }
      y += rowHeight + lineSpacing
    }
  }

  /// A row with any trailing separators removed.
  private func visible(_ row: [Int], separators: [Bool]) -> [Int] {
    var row = row
    while let last = row.last, separators[last] { row.removeLast() }
    return row
  }

  private func rowWidth(_ row: [Int], sizes: [CGSize]) -> CGFloat {
    row.map { sizes[$0].width }.reduce(0, +) + itemSpacing * CGFloat(max(0, row.count - 1))
  }

  private func rows(maxWidth: CGFloat, sizes: [CGSize], separators: [Bool]) -> [[Int]] {
    var rows: [[Int]] = []
    var row: [Int] = []
    var x: CGFloat = 0
    for index in sizes.indices {
      let width = sizes[index].width
      // Separators never wrap; they stay glued to the line of the preceding name.
      if !separators[index], !row.isEmpty, x + itemSpacing + width > maxWidth {
        rows.append(row)
        row = []
        x = 0
      }
      if !row.isEmpty { x += itemSpacing }
      row.append(index)
      x += width
    }
    if !row.isEmpty { rows.append(row) }
    return rows
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
              let translatorList = translators[language] ?? []
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
