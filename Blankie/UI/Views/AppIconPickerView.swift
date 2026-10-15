//
//  AppIconPickerView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/11/26.
//

import SwiftUI
import os

#if os(iOS)
  import UIKit

  /// Settings sub-page for choosing the app icon: a grid of icon tiles with
  /// an accent ring on the current selection.
  struct AppIconPickerView: View {
    /// An available app icon (primary or alternate).
    private struct AppIconOption: Identifiable {
      let id = UUID()
      let name: String?  // nil for primary icon
      let displayName: String
      let image: UIImage?
    }

    private let globalSettings = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var options: [AppIconOption] = []
    @State private var currentIconName: String? = UIApplication.shared.alternateIconName

    var body: some View {
      ScrollView {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3),
          spacing: 24
        ) {
          ForEach(options) { option in
            iconCell(for: option)
          }
        }
        .padding()
      }
      .navigationTitle(Text("App Icon"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .tint(Color.primary)
        }
      }
      .onAppear { options = Self.availableAppIcons() }
      .tint(globalSettings.customAccentColor ?? .accentColor)
    }

    private func iconCell(for option: AppIconOption) -> some View {
      let isSelected = option.name == currentIconName
      return Button {
        setAppIcon(option.name)
      } label: {
        if let image = option.image {
          // Fill the grid column; the ring radius tracks the system
          // app-icon corner ratio (~22.5% of size) at any tile size.
          GeometryReader { geo in
            let radius = geo.size.width * 0.225
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                  .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
              )
          }
          .aspectRatio(1, contentMode: .fit)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(option.displayName))
      .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private static func availableAppIcons() -> [AppIconOption] {
      var options: [AppIconOption] = []

      let primaryImage = UIImage(named: "BlankieAppIconDisplay") ?? UIImage(systemName: "app.fill")
      options.append(
        AppIconOption(
          name: nil,
          displayName: String(localized: "Default"),
          image: primaryImage
        ))

      // Color variants mirror the in-app accent palette (AccentColor).
      var knownAlternates: [(key: String, displayName: String)] = [
        ("BlankieRedIcon", String(localized: "Red")),
        ("BlankiePinkIcon", String(localized: "Pink")),
        ("BlankieOrangeIcon", String(localized: "Orange")),
        ("BlankieBrownIcon", String(localized: "Brown")),
        ("BlankieYellowIcon", String(localized: "Yellow")),
        ("BlankieGreenIcon", String(localized: "Green")),
        ("BlankieMintIcon", String(localized: "Mint")),
        ("BlankieTealIcon", String(localized: "Teal")),
        ("BlankieCyanIcon", String(localized: "Cyan")),
        ("BlankieBlueIcon", String(localized: "Blue")),
        ("BlankieIndigoIcon", String(localized: "Indigo")),
        ("BlankiePurpleIcon", String(localized: "Purple")),
        ("BlankieDarkIcon", String(localized: "Dark")),
        ("BlankieSliderIcon", String(localized: "Slider")),
        ("BlankieAltIcon", String(localized: "Alternative")),
        ("BlankieWavesIcon", String(localized: "appIcon.waves", defaultValue: "Waves")),
        ("BlankieClassicIcon", String(localized: "Classic")),
        ("BlankiePatchworkIcon", String(localized: "Inspired by Blanket by Rafael Mardojai CM")),
      ]

      // Leopard is a developer-only icon, surfaced only in local Debug builds.
      #if DEBUG
        knownAlternates.append(("BlankieLeopardIcon", String(localized: "Leopard")))
      #endif

      for alternate in knownAlternates {
        // Display assets only: UIImage(named:) on a .icon-compiled name throws
        // NSInternalInconsistencyException rather than returning nil.
        let image =
          UIImage(named: "\(alternate.key)Display") ?? UIImage(systemName: "app.fill")
        options.append(
          AppIconOption(name: alternate.key, displayName: alternate.displayName, image: image))
      }

      // The display assets are 1024px; drawing them at tile size aliases badly
      // (and holds ~70 MB of bitmaps). Downsample once with a proper filter.
      return options.map { option in
        AppIconOption(
          name: option.name,
          displayName: option.displayName,
          image: option.image?.preparingThumbnail(of: CGSize(width: 360, height: 360))
            ?? option.image)
      }
    }

    private func setAppIcon(_ name: String?) {
      guard UIApplication.shared.supportsAlternateIcons else { return }
      UIApplication.shared.setAlternateIconName(name) { error in
        if let error = error {
          Logger.ui.error("AppIconPickerView: Failed to set app icon: \(error, privacy: .public)")
        } else {
          Logger.ui.debug("AppIconPickerView: App icon changed to \(name ?? "Default")")
          DispatchQueue.main.async {
            currentIconName = name
            dismiss()
          }
        }
      }
    }
  }

  #Preview {
    NavigationStack {
      AppIconPickerView()
    }
  }
#endif
