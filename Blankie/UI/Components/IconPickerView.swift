//
//  IconPickerView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

struct IconPickerView: View {
  @Binding var selectedIcon: String
  @State private var iconSearchText = ""
  @State private var selectedIconCategory: String
  @Environment(\.dismiss) private var dismiss

  // Icon categories with curated selections
  private let iconCategories = IconData.iconCategories

  init(selectedIcon: Binding<String>) {
    self._selectedIcon = selectedIcon

    // Find which category contains the selected icon
    let categories = IconData.iconCategories
    var foundCategory = "Popular"  // Default fallback

    for (categoryName, icons) in categories where icons.contains(selectedIcon.wrappedValue) {
      foundCategory = categoryName
      break
    }

    self._selectedIconCategory = State(initialValue: foundCategory)
  }

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
    VStack(spacing: 0) {
      // Search and category picker
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          HStack {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
            TextField(text: $iconSearchText) {
              Text("Search icons...")
            }
            .textFieldStyle(.plain)

            if !iconSearchText.isEmpty {
              Button {
                iconSearchText = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(8)
          .background(
            Group {
              #if os(macOS)
                Color(NSColor.controlBackgroundColor)
              #else
                Color(UIColor.secondarySystemBackground)
              #endif
            }
          )
          .clipShape(RoundedRectangle(cornerRadius: 8))

          if iconSearchText.isEmpty {
            Picker(
              selection: $selectedIconCategory,
              label: Text("Category")
            ) {
              ForEach(Array(iconCategories.keys).sorted(), id: \.self) { category in
                Text(category).tag(category)
              }
            }
            .pickerStyle(.menu)
            .labelsHidden()
          }
        }
        .padding()

        Divider()
      }

      // Icon grid
      ScrollViewReader { proxy in
        ScrollView {
          if searchResults.isEmpty && !iconSearchText.isEmpty {
            VStack(spacing: 12) {
              Image(systemName: "questionmark.square.dashed")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No matching icons found")
                .font(.headline)
              Text(
                "Try a different search term"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
          } else {
            LazyVGrid(
              columns: [
                GridItem(.adaptive(minimum: 60), spacing: 12)
              ],
              spacing: 12
            ) {
              ForEach(searchResults, id: \.self) { iconName in
                Button {
                  selectedIcon = iconName
                  dismiss()
                } label: {
                  VStack(spacing: 4) {
                    Image(systemName: iconName)
                      .font(.system(size: 28))
                      .frame(height: 32)
                  }
                  .frame(width: 60, height: 60)
                  .background(
                    selectedIcon == iconName
                      ? Color.accentColor.opacity(0.2)
                      : Color.primary.opacity(0.05)
                  )
                  .clipShape(RoundedRectangle(cornerRadius: 10))
                  .overlay(
                    RoundedRectangle(cornerRadius: 10)
                      .stroke(
                        selectedIcon == iconName ? Color.accentColor : Color.clear,
                        lineWidth: 2
                      )
                  )
                }
                .buttonStyle(.plain)
                .help(iconName)
                .id(iconName)  // Add ID for scrolling
              }
            }
            .padding()
          }
        }
        .onAppear {
          // Scroll to the selected icon when the view appears
          if searchResults.contains(selectedIcon) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              withAnimation {
                proxy.scrollTo(selectedIcon, anchor: .center)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Choose Icon")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
  }
}

// Extract icon data loading to a shared struct
struct IconData {
  static let iconCategories: [String: [String]] = loadIconCategories()

  private static func loadIconCategories() -> [String: [String]] {
    // Helper enum to decode JSON with nested categories
    enum IconCategory: Decodable {
      case simple([String])
      case nested([String: [String]])

      var allIcons: [String] {
        switch self {
        case .simple(let icons):
          return icons
        case .nested(let subcategories):
          return subcategories.values.flatMap { $0 }
        }
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let icons = try? container.decode([String].self) {
          self = .simple(icons)
        } else if let subcategories = try? container.decode([String: [String]].self) {
          self = .nested(subcategories)
        } else {
          throw DecodingError.typeMismatch(
            IconCategory.self,
            DecodingError.Context(
              codingPath: decoder.codingPath,
              debugDescription: "Expected array or dictionary"
            )
          )
        }
      }
    }

    guard let url = Bundle.main.url(forResource: "icon-categories", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let categories = try? JSONDecoder().decode([String: IconCategory].self, from: data)
    else {
      return [:]
    }

    // Flatten nested categories
    var flatCategories: [String: [String]] = [:]
    for (key, value) in categories {
      flatCategories[key] = value.allIcons
    }
    return flatCategories
  }
}

// MARK: - Previews

#Preview {
  @Previewable @State var selectedIcon = "waveform.circle"

  NavigationStack {
    IconPickerView(selectedIcon: $selectedIcon)
  }
}
