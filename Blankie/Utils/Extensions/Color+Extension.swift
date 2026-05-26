//
//  AccentColor.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

enum AccentColor: CaseIterable {
  case system
  case red
  case pink
  case orange
  case brown
  case yellow
  case green
  case mint
  case teal
  case cyan
  case blue
  case indigo
  case purple

  var name: String {
    switch self {
    case .system: return String(localized: "System")
    case .red: return String(localized: "Red")
    case .pink: return String(localized: "Pink")
    case .orange: return String(localized: "Orange")
    case .brown: return String(localized: "Brown")
    case .yellow: return String(localized: "Yellow")
    case .green: return String(localized: "Green")
    case .mint: return String(localized: "Mint")
    case .teal: return String(localized: "Teal")
    case .cyan: return String(localized: "Cyan")
    case .blue: return String(localized: "Blue")
    case .indigo: return String(localized: "Indigo")
    case .purple: return String(localized: "Purple")
    }
  }

  var color: Color? {
    switch self {
    case .system: return nil
    case .red: return .red
    case .pink: return .pink
    case .orange: return .orange
    case .brown: return .brown
    case .yellow: return .yellow
    case .green: return .green
    case .mint: return .mint
    case .teal: return .teal
    case .cyan: return .cyan
    case .blue: return .blue
    case .indigo: return .indigo
    case .purple: return .purple
    }
  }
}

enum AppearanceMode: String, CaseIterable {
  case system
  case light
  case dark

  var localizedName: String {
    switch self {
    case .system: return String(localized: "Automatic")
    case .light: return String(localized: "Light")
    case .dark: return String(localized: "Dark")
    }
  }

  var icon: String {
    switch self {
    case .system: return "circle.lefthalf.filled"
    case .light: return "sun.max.fill"
    case .dark: return "moon.fill"
    }
  }

  var displayName: String {
    localizedName
  }
}

extension Color {
  var toString: String {
    switch self {
    case .red: return "red"
    case .pink: return "pink"
    case .orange: return "orange"
    case .brown: return "brown"
    case .yellow: return "yellow"
    case .green: return "green"
    case .mint: return "mint"
    case .teal: return "teal"
    case .cyan: return "cyan"
    case .blue: return "blue"
    case .indigo: return "indigo"
    case .purple: return "purple"
    default: return ""
    }
  }

  private static let colorMap: [String: Color] = [
    "red": .red,
    "pink": .pink,
    "orange": .orange,
    "brown": .brown,
    "yellow": .yellow,
    "green": .green,
    "mint": .mint,
    "teal": .teal,
    "cyan": .cyan,
    "blue": .blue,
    "indigo": .indigo,
    "purple": .purple,
  ]

  init?(fromString string: String) {
    if let color = Self.colorMap[string] {
      self = color
    } else {
      return nil
    }
  }
}
