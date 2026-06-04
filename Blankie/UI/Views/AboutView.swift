//
//  AboutView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI

#if os(iOS)
  import TipKit
  import UIKit

  extension UIApplication {
    /// Returns the currently active app icon image (supports alternate icons), falling back to the primary icon
    var currentAppIcon: UIImage? {
      // iOS 18: .icon files cannot be loaded with UIImage(named:)
      // We need to look for matching display assets in the asset catalog

      // If an alternate icon is active, try to load its display asset
      if let altName = UIApplication.shared.alternateIconName {
        // Try loading from asset catalog with "Display" suffix
        if let image = UIImage(named: "\(altName)Display") {
          return image
        }
        // Try loading the alternate icon directly (works for legacy PNG sets like BetaIcon)
        if let image = UIImage(named: altName) {
          return image
        }
        debugLog("AboutView: Unable to load alternate icon image '\(altName)'; falling back", .ui)
      }

      // Try primary icon display asset
      if let image = UIImage(named: "BlankieAppIconDisplay") {
        return image
      }

      // Fallback to BetaIcon if it exists (has legacy PNGs)
      if let image = UIImage(named: "BetaIcon") {
        return image
      }

      // Ultimate fallback to a system symbol so the About header never appears empty
      return UIImage(systemName: "app.fill")
    }
  }

  /// Represents an available app icon option (primary or alternate)
  private struct AppIconOption: Identifiable {
    let id = UUID()
    let name: String?  // nil for primary icon
    let displayName: String
    let image: UIImage?
  }

  private struct AppIconChangeTip: Tip {
    var title: Text { Text("Change App Icon") }
    var message: Text? { Text("Tap to choose Default, Classic, or Beta.") }
  }
#endif

struct AboutView: View {
  @ObservedObject private var creditsManager = SoundCreditsManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isSoundCreditsExpanded = false
  @State private var isLicenseExpanded = false
  @State private var isAcknowledgementsExpanded = false
  @State private var contributors: [String] = []
  @State private var translators: [String: [String]] = [:]

  #if os(iOS)
    @State private var showingIconChooser = false
    @State private var appIconOptions: [AppIconOption] = []
    @State private var currentIconName: String? = UIApplication.shared.alternateIconName
  #endif

  private let appVersion =
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
  private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

  var body: some View {
    Group {
      #if os(iOS)
        NavigationStack {
          aboutContent
            .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") { dismiss() }
                  .tint(Color.primary)
              }
            }
        }
      #else
        aboutContent.frame(width: 480, height: 650)
      #endif
    }
  }

  private var aboutContent: some View {
    ScrollView {
      VStack(spacing: 20) {
        #if os(macOS)
          macOSCloseButton
        #endif

        appIconView
        appInfoSection
        linksSection

        InspirationSection()
        Divider().padding(.horizontal, 40).accessibilityHidden(true)
        DeveloperSection()

        if !contributors.isEmpty {
          Divider().padding(.horizontal, 40).accessibilityHidden(true)
          ContributorSection(contributors: contributors)
        }

        if !translators.isEmpty {
          Divider().padding(.horizontal, 40).accessibilityHidden(true)
          TranslatorSection(translators: translators)
        }

        Divider().padding(.horizontal, 40).accessibilityHidden(true)
        copyrightText
        creditsAndLicenseSection
        Divider().padding(.horizontal, 40).accessibilityHidden(true)
        helpSection
      }
      .padding(20)
      #if os(iOS)
        .sheet(isPresented: $showingIconChooser) {
          iconChooserSheet
        }
      #endif
    }
    .onAppear {
      loadCredits()
      #if os(iOS)
        appIconOptions = getAvailableAppIcons()
        try? Tips.configure()
      #endif
    }
    // Tint the About content once so link/help icons that use Color.accentColor
    // resolve from the same environment as tinted rows (e.g. InspirationSection),
    // so one interaction can't flip them between system blue and the app accent.
    .tint(globalSettings.customAccentColor ?? .accentColor)
  }
}

// MARK: - View Components

extension AboutView {
  #if os(macOS)
    private var macOSCloseButton: some View {
      HStack {
        Spacer()
        Button(action: { dismiss() }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
            .imageScale(.large)
        }
        .buttonStyle(.plain)
        .help("Close")
        .accessibilityLabel(Text("Close"))
        .keyboardShortcut(.defaultAction)
      }
      .padding(.bottom, -8)
    }
  #endif

  private var appIconView: some View {
    Group {
      #if os(iOS)
        if let appIcon = UIApplication.shared.currentAppIcon {
          VStack(spacing: 6) {
            Image(uiImage: appIcon)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 100, height: 100)
              .cornerRadius(20)
              .contentShape(RoundedRectangle(cornerRadius: 20))
              .onTapGesture {
                appIconOptions = getAvailableAppIcons()
                showingIconChooser = appIconOptions.count > 1
              }
              .accessibilityAddTraits(.isButton)
              .accessibilityLabel(Text("Change app icon"))
          }
          .popoverTip(AppIconChangeTip(), arrowEdge: .bottom)
        }
      #elseif os(macOS)
        if let appIcon = NSApplication.shared.applicationIconImage {
          Image(nsImage: appIcon)
            .resizable()
            .frame(width: 128, height: 128)
            // Non-interactive on macOS; give it a description rather than a bare image.
            .accessibilityLabel(Text("Blankie app icon"))
        }
      #endif
    }
  }

  private var appInfoSection: some View {
    VStack(spacing: 8) {
      Text(verbatim: "Blankie")
        .font(.system(.title2, design: .rounded).weight(.medium))
        #if os(iOS)
          .onTapGesture {
            appIconOptions = getAvailableAppIcons()
            showingIconChooser = appIconOptions.count > 1
          }
          .accessibilityAddTraits(.isButton)
          .accessibilityHint(Text("Change app icon"))
        #endif

      Text(LocalizedStringKey("Version \(appVersion) (\(buildNumber))"))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var linksSection: some View {
    let linksLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
    return linksLayout {
      HStack(spacing: 4) {
        Image(systemName: "globe")
          .accessibilityHidden(true)
        Link("blankie.rest", destination: URL(string: "https://blankie.rest")!).handCursor()
      }

      Link(destination: URL(string: "https://github.com/codybrom/blankie")!) {
        HStack(spacing: 4) {
          Image(systemName: "star.fill").foregroundStyle(.yellow)
          Text("Star on GitHub")
        }
      }
      .handCursor()

      Link(destination: URL(string: "https://github.com/codybrom/blankie/issues")!) {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Text("Report an Issue")
        }
      }
      .handCursor()
    }
    .font(.caption)
  }

  private var copyrightText: some View {
    Text("© 2026 Cody Bromley and contributors. All rights reserved.")
      .font(.caption)
  }

  private var creditsAndLicenseSection: some View {
    VStack(spacing: 12) {
      ExpandableSection(
        title: "Sound Credits",
        isExpanded: $isSoundCreditsExpanded,
        onExpand: {
          isLicenseExpanded = false
          isAcknowledgementsExpanded = false
        }
      ) {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(creditsManager.credits, id: \.name) { credit in
            CreditRow(credit: credit)
          }
        }
      }

      ExpandableSection(
        title: "Software License",
        isExpanded: $isLicenseExpanded,
        onExpand: {
          isSoundCreditsExpanded = false
          isAcknowledgementsExpanded = false
        }
      ) {
        SoftwareLicenseSection()
      }

      ExpandableSection(
        title: "Acknowledgements",
        isExpanded: $isAcknowledgementsExpanded,
        onExpand: {
          isSoundCreditsExpanded = false
          isLicenseExpanded = false
        }
      ) {
        AcknowledgementsSection()
      }
    }
  }

  private var helpSection: some View {
    Link(destination: URL(string: "https://blankie.rest/faq")!) {
      HStack {
        Image(systemName: "questionmark.circle").foregroundColor(.accentColor)
          .accessibilityHidden(true)
        Text("Blankie Help").foregroundColor(.primary)
        Spacer()
        Image(systemName: "safari").foregroundColor(.secondary)
          .accessibilityHidden(true)
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
      .background(.regularMaterial)
      .cornerRadius(8)
    }
    .handCursor()
  }
}

// MARK: - iOS App Icon Chooser

#if os(iOS)
  extension AboutView {
    private var iconChooserSheet: some View {
      NavigationStack {
        List(appIconOptions) { option in
          Button {
            setAppIcon(option.name)
            showingIconChooser = false
          } label: {
            HStack(spacing: 12) {
              if let image = option.image {
                Image(uiImage: image)
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 60, height: 60)
                  .cornerRadius(13)
                  .accessibilityHidden(true)
              }
              Text(option.displayName).foregroundColor(.primary)
              Spacer()
              if option.name == UIApplication.shared.alternateIconName {
                Image(systemName: "checkmark")
                  .foregroundColor(.accentColor)
                  .accessibilityHidden(true)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(
            option.name == UIApplication.shared.alternateIconName ? [.isSelected] : [])
        }
        .navigationTitle(Text("Choose App Icon"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { showingIconChooser = false }
              .tint(Color.primary)
          }
        }
      }
      .tint(globalSettings.customAccentColor ?? .accentColor)
      .presentationDetents([.medium])
    }

    private func getAvailableAppIcons() -> [AppIconOption] {
      var options: [AppIconOption] = []

      let primaryImage = UIImage(named: "BlankieAppIconDisplay") ?? UIImage(systemName: "app.fill")
      options.append(
        AppIconOption(
          name: nil,
          displayName: String(localized: "Default"),
          image: primaryImage
        ))

      let knownAlternates: [(key: String, displayName: String)] = [
        (
          "BlankieAltIcon", String(localized: "Alternative")
        ),
        ("BlankieClassicIcon", String(localized: "Classic")),
        ("BetaIcon", String(localized: "Beta")),
      ]

      for alternate in knownAlternates {
        let image =
          UIImage(named: "\(alternate.key)Display") ?? UIImage(named: alternate.key)
          ?? UIImage(systemName: "app.fill")
        options.append(
          AppIconOption(name: alternate.key, displayName: alternate.displayName, image: image))
      }

      return options
    }

    private func setAppIcon(_ name: String?) {
      guard UIApplication.shared.supportsAlternateIcons else { return }
      UIApplication.shared.setAlternateIconName(name) { error in
        if let error = error {
          logError("AboutView: Failed to set app icon: \(error)", .ui)
        } else {
          debugLog("AboutView: App icon changed to \(name ?? "Default")", .ui)
          DispatchQueue.main.async {
            currentIconName = name
          }
        }
      }
    }
  }
#endif

// MARK: - Data Loading

extension AboutView {
  private func loadCredits() {
    guard let url = Bundle.main.url(forResource: "credits", withExtension: "json") else {
      debugLog("Unable to find credits.json in bundle", .ui)
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let credits = try decoder.decode(Credits.self, from: data)
      contributors = credits.contributors
      translators = credits.translators
    } catch {
      logError("Error loading credits: \(error)", .ui)
    }
  }
}

#Preview {
  AboutView()
    .modelContainer(for: [CustomSoundData.self, PresetArtwork.self])
}
