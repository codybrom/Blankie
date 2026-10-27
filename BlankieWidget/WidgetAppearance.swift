//
//  WidgetAppearance.swift
//  BlankieWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// Stored in each widget's configuration, independent of the app's settings.
enum WidgetColorChoice: String, AppEnum {
  case defaultAccent, red, pink, orange, brown, yellow, green, mint, teal, cyan, blue,
    indigo, purple

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Widget Color" }
  // Match AccentColor's existing Localizable.xcstrings keys exactly. The
  // widget bundles that shared catalog, including its color translations.
  static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
    [
      .defaultAccent: "Default",
      .blue: "Blue", .purple: "Purple", .pink: "Pink", .red: "Red", .orange: "Orange",
      .brown: "Brown", .yellow: "Yellow", .green: "Green", .mint: "Mint", .teal: "Teal",
      .cyan: "Cyan", .indigo: "Indigo",
    ]
  }

  @MainActor
  func accent(defaultName: String?) -> Color {
    switch self {
    case .defaultAccent: widgetAccentColor(defaultName)
    default: widgetAccentColor(rawValue)
    }
  }
}

struct WidgetAppearanceIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Widget Appearance" }
  static var description: IntentDescription {
    IntentDescription("Choose a color for this widget.")
  }

  @Parameter(title: "Color", default: .defaultAccent)
  var color: WidgetColorChoice
}

private struct WidgetForegroundKey: EnvironmentKey {
  static let defaultValue: Color = .white
}

extension EnvironmentValues {
  var widgetForeground: Color {
    get { self[WidgetForegroundKey.self] }
    set { self[WidgetForegroundKey.self] = newValue }
  }
}

/// WidgetKit can replace this removable background with Tinted/Clear styling.
struct WidgetAppearanceBackground: View {
  @Environment(\.colorScheme) private var colorScheme
  let choice: WidgetColorChoice
  let defaultAccentName: String?

  var body: some View {
    widgetAccentGradient(choice.accent(defaultName: defaultAccentName), colorScheme: colorScheme)
  }
}

/// The portrait XL family needs iOS/macOS 27; older systems get medium and large.
var interactiveWidgetFamilies: [WidgetFamily] {
  if #available(iOS 27.0, macOS 27.0, *) {
    return [.systemMedium, .systemLarge, .systemExtraLargePortrait]
  }
  return [.systemMedium, .systemLarge]
}

extension WidgetFamily {
  var isExtraLargePortrait: Bool {
    if #available(iOS 27.0, macOS 27.0, *) {
      return self == .systemExtraLargePortrait
    }
    return false
  }
}
