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
        debugLog("⚠️ AboutView: Unable to load alternate icon image '\(altName)'; falling back")
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
  @Environment(\.dismiss) private var dismiss
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
        Divider().padding(.horizontal, 40)
        DeveloperSection()

        if !contributors.isEmpty {
          Divider().padding(.horizontal, 40)
          ContributorSection(contributors: contributors)
        }

        if !translators.isEmpty {
          Divider().padding(.horizontal, 40)
          TranslatorSection(translators: translators)
        }

        Divider().padding(.horizontal, 40)
        copyrightText
        creditsAndLicenseSection
        Divider().padding(.horizontal, 40)
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
          }
          .popoverTip(AppIconChangeTip(), arrowEdge: .bottom)
        }
      #elseif os(macOS)
        if let appIcon = NSApplication.shared.applicationIconImage {
          Image(nsImage: appIcon)
            .resizable()
            .frame(width: 128, height: 128)
        }
      #endif
    }
  }

  private var appInfoSection: some View {
    VStack(spacing: 8) {
      Text(verbatim: "Blankie")
        .font(.system(size: 24, weight: .medium, design: .rounded))
        #if os(iOS)
          .onTapGesture {
            appIconOptions = getAvailableAppIcons()
            showingIconChooser = appIconOptions.count > 1
          }
          .accessibilityAddTraits(.isButton)
        #endif

      Text(LocalizedStringKey("Version \(appVersion) (\(buildNumber))"), comment: "Version string")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
  }

  private var linksSection: some View {
    HStack(spacing: 16) {
      HStack(spacing: 4) {
        Image(systemName: "globe")
        Link("blankie.rest", destination: URL(string: "https://blankie.rest")!).handCursor()
      }

      Link(destination: URL(string: "https://github.com/codybrom/blankie")!) {
        HStack(spacing: 4) {
          Image(systemName: "star.fill").foregroundStyle(.yellow)
          Text("Star on GitHub", comment: "Star on GitHub label")
        }
      }
      .handCursor()

      Link(destination: URL(string: "https://github.com/codybrom/blankie/issues")!) {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Text("Report an Issue", comment: "Report an issue label")
        }
      }
      .handCursor()
    }
    .font(.system(size: 12))
  }

  private var copyrightText: some View {
    Text("© 2025 Cody Bromley and contributors. All rights reserved.")
      .font(.caption)
  }

  private var creditsAndLicenseSection: some View {
    VStack(spacing: 12) {
      ExpandableSection(
        title: "Sound Credits",
        comment: "Expandable section title: Sound Credits",
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
        comment: "Expandable section title: Software License",
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
        comment: "Expandable section title: Acknowledgements",
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
        Text("Blankie Help", comment: "Help and FAQ link label").foregroundColor(.primary)
        Spacer()
        Image(systemName: "safari").foregroundColor(.secondary)
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
              }
              Text(option.displayName).foregroundColor(.primary)
              Spacer()
              if option.name == UIApplication.shared.alternateIconName {
                Image(systemName: "checkmark").foregroundColor(.accentColor)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        .navigationTitle(Text("Choose App Icon", comment: "App icon selection dialog title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { showingIconChooser = false }
          }
        }
      }
      .presentationDetents([.medium])
    }

    private func getAvailableAppIcons() -> [AppIconOption] {
      var options: [AppIconOption] = []

      let primaryImage = UIImage(named: "BlankieAppIconDisplay") ?? UIImage(systemName: "app.fill")
      options.append(
        AppIconOption(
          name: nil,
          displayName: NSLocalizedString("Default", comment: "Default app icon option"),
          image: primaryImage
        ))

      let knownAlternates: [(key: String, displayName: String)] = [
        (
          "BlankieAltIcon", NSLocalizedString("Alternative", comment: "Alternative app icon option")
        ),
        ("BlankieClassicIcon", NSLocalizedString("Classic", comment: "Classic app icon option")),
        ("BetaIcon", NSLocalizedString("Beta", comment: "Beta app icon option")),
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
          debugLog("❌ AboutView: Failed to set app icon: \(error)")
        } else {
          debugLog("✅ AboutView: App icon changed to \(name ?? "Default")")
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
      debugLog("Unable to find credits.json in bundle")
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let credits = try decoder.decode(Credits.self, from: data)
      contributors = credits.contributors
      translators = credits.translators
    } catch {
      debugLog("Error loading credits: \(error)")
    }
  }
}

#Preview {
  AboutView()
    .modelContainer(for: [CustomSoundData.self, PresetArtwork.self])
}
