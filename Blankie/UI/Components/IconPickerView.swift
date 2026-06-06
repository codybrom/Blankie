//
//  IconPickerView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import SwiftUI

/// Curated icon categories. Raw values match the top-level keys in icon-categories.json.
enum IconCategory: String, CaseIterable {
  case popular = "Popular"
  case nature = "Nature"
  case audio = "Audio"
  case education = "Education"
  case sports = "Sports"
  case tools = "Tools"
  case objects = "Objects"
  case home = "Home"
  case transport = "Transport"
  case communication = "Communication"
  case shopping = "Shopping"
  case foodAndDrink = "Food & Drink"
  case entertainment = "Entertainment"
  case medical = "Medical"
  case clothing = "Clothing"
  case miscellaneous = "Miscellaneous"
  case symbols = "Symbols"
  case peopleAndActivity = "People & Activity"

  var localizedName: String {
    switch self {
    case .popular: return String(localized: "Popular")
    case .nature: return String(localized: "Nature")
    case .audio: return String(localized: "Audio")
    case .education: return String(localized: "Education")
    case .sports: return String(localized: "Sports")
    case .tools: return String(localized: "Tools")
    case .objects: return String(localized: "Objects")
    case .home: return String(localized: "Home")
    case .transport: return String(localized: "Transport")
    case .communication: return String(localized: "Communication")
    case .shopping: return String(localized: "Shopping")
    case .foodAndDrink: return String(localized: "Food & Drink")
    case .entertainment: return String(localized: "Entertainment")
    case .medical: return String(localized: "Medical")
    case .clothing: return String(localized: "Clothing")
    case .miscellaneous: return String(localized: "Miscellaneous")
    case .symbols: return String(localized: "Symbols")
    case .peopleAndActivity: return String(localized: "People & Activity")
    }
  }

  /// Categories sorted by localized display name for picker menus.
  static var sortedByLocalizedName: [IconCategory] {
    allCases.sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
  }

  var icons: [String] {
    IconData.iconCategories[rawValue] ?? []
  }
}

struct IconPickerView: View {
  @Binding var selectedIcon: String
  @State private var iconSearchText = ""
  @State private var selectedIconCategory: IconCategory
  @Environment(\.dismiss) private var dismiss

  // Icon categories with curated selections
  private let iconCategories = IconData.iconCategories

  init(selectedIcon: Binding<String>) {
    self._selectedIcon = selectedIcon

    // Find which category contains the selected icon
    let foundCategory =
      IconCategory.allCases.first { $0.icons.contains(selectedIcon.wrappedValue) } ?? .popular

    self._selectedIconCategory = State(initialValue: foundCategory)
  }

  private var searchResults: [String] {
    if iconSearchText.isEmpty {
      return selectedIconCategory.icons
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
              .accessibilityHidden(true)
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
              .accessibilityLabel(Text("Clear search"))
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
              ForEach(IconCategory.sortedByLocalizedName, id: \.self) { category in
                Text(category.localizedName).tag(category)
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
                .accessibilityHidden(true)
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
                // Read the symbol name without VoiceOver speaking each "dot".
                .accessibilityLabel(Text(iconName.replacingOccurrences(of: ".", with: " ")))
                .accessibilityAddTraits(selectedIcon == iconName ? .isSelected : [])
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

  /// Every pickable symbol, for validating AI icon suggestions against the
  /// real catalog (which already excludes restricted symbols).
  static let allIcons: Set<String> = Set(iconCategories.values.flatMap { $0 })

  /// Category names, for constraining the AI icon pick's first stage.
  static let categoryNames: [String] = iconCategories.keys.sorted()

  private static func loadIconCategories() -> [String: [String]] {
    // Helper enum to decode JSON with nested categories
    enum CategoryEntry: Decodable {
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
            CategoryEntry.self,
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
      let categories = try? JSONDecoder().decode([String: CategoryEntry].self, from: data)
    else {
      return [:]
    }

    // Flatten nested categories
    var flatCategories: [String: [String]] = [:]
    for (key, value) in categories {
      assert(
        IconCategory(rawValue: key) != nil,
        "icon-categories.json key '\(key)' has no IconCategory case")
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
