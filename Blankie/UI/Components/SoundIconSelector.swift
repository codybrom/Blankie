//
//  SoundIconSelector.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

struct SoundIconSelector: View {
  @Binding var selectedIcon: String
  @State private var iconSearchText = ""
  @State private var selectedIconCategory = "Popular"

  // Icon categories with curated selections
  private let iconCategories = IconData.iconCategories

  private var searchResults: [String] {
    if iconSearchText.isEmpty {
      return iconCategories[selectedIconCategory] ?? []
    }

    // Search across all categories
    let allIcons = iconCategories.values.flatMap { $0 }
    let uniqueIcons = Array(Set(allIcons))

    return uniqueIcons.filter { icon in
      icon.localizedCaseInsensitiveContains(iconSearchText)
    }.sorted()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Icon", comment: "Icon selection label")
          .font(.headline)
        Spacer()
        Text("Selected:", comment: "Selected icon label")
        Image(systemName: selectedIcon)
          .font(.title2)
          .foregroundStyle(.tint)
      }

      // Search and category picker
      HStack(spacing: 8) {
        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField(text: $iconSearchText) {
            Text("Search icons...", comment: "Icon search field placeholder")
          }
          .textFieldStyle(.plain)
        }
        .padding(6)
        .background(
          Group {
            #if os(macOS)
              Color(NSColor.controlBackgroundColor)
            #else
              Color(UIColor.systemBackground)
            #endif
          }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))

        if iconSearchText.isEmpty {
          Picker(
            selection: $selectedIconCategory,
            label: Text("Category", comment: "Icon category picker label")
          ) {
            ForEach(Array(iconCategories.keys).sorted(), id: \.self) { category in
              Text(category).tag(category)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .frame(width: 120)
        }
      }

      ScrollView {
        if searchResults.isEmpty && !iconSearchText.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "questionmark.square.dashed")
              .font(.largeTitle)
              .foregroundStyle(.tertiary)
            Text("No matching icons found", comment: "No icon search results message")
              .font(.headline)
            Text(
              "Try a different search term",
              comment: "No icon search results suggestion"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 40)
        } else {
          LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(50), spacing: 8), count: 6),
            spacing: 8
          ) {
            ForEach(searchResults, id: \.self) { iconName in
              Button {
                selectedIcon = iconName
              } label: {
                VStack(spacing: 4) {
                  Image(systemName: iconName)
                    .font(.system(size: 24))
                    .frame(height: 30)
                }
                .frame(width: 50, height: 50)
                .background(
                  selectedIcon == iconName
                    ? Color.accentColor.opacity(0.2)
                    : Color.primary.opacity(0.05)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(
                      selectedIcon == iconName ? Color.accentColor : Color.clear,
                      lineWidth: 2
                    )
                )
              }
              .buttonStyle(.plain)
              .help(iconName)
            }
          }
          .padding(4)
        }
      }
      .frame(height: 200)
      .background(
        Group {
          #if os(macOS)
            Color(NSColor.textBackgroundColor)
          #else
            Color(UIColor.systemBackground)
          #endif
        }
      )
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

// MARK: - Previews

#Preview {
  @Previewable @State var selectedIcon = "waveform.circle"

  SoundIconSelector(selectedIcon: $selectedIcon)
    .padding()
    .frame(width: 450)
}
