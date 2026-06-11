//
//  AboutView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI
import os

#if os(iOS)
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
        // Try loading the alternate icon directly
        if let image = UIImage(named: altName) {
          return image
        }
        Logger.ui.debug("AboutView: Unable to load alternate icon image '\(altName)'; falling back")
      }

      // Try primary icon display asset
      if let image = UIImage(named: "BlankieAppIconDisplay") {
        return image
      }

      // Ultimate fallback to a system symbol so the About header never appears empty
      return UIImage(systemName: "app.fill")
    }
  }

#endif

struct AboutView: View {
  @ObservedObject private var creditsManager = SoundCreditsManager.shared
  private let globalSettings = GlobalSettings.shared
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isSoundCreditsExpanded = false
  @State private var isLicenseExpanded = false
  @State private var isAcknowledgementsExpanded = false
  @State private var contributors: [String] = []
  @State private var betaTesters: [String] = []
  @State private var translators: [String: [String]] = [:]

  private let appVersion =
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
  private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

  // Shown only as a Settings sub-page: pushed in the iOS settings sheet's
  // stack, swapped into the macOS Settings pane.
  var body: some View {
    aboutContent
      .navigationTitle("About Blankie")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
  }

  private var aboutContent: some View {
    ScrollView {
      VStack(spacing: 20) {
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

        if !betaTesters.isEmpty {
          Divider().padding(.horizontal, 40).accessibilityHidden(true)
          ContributorSection(title: "Beta Testers", contributors: betaTesters)
        }

        Divider().padding(.horizontal, 40).accessibilityHidden(true)
        copyrightText
        creditsAndLicenseSection
      }
      .padding(20)
      // Readable column in the wide Settings pane; no-op in the iOS sheet.
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .onAppear {
      loadCredits()
    }
    // Tint the About content once so link/help icons that use Color.accentColor
    // resolve from the same environment as tinted rows (e.g. InspirationSection),
    // so one interaction can't flip them between system blue and the app accent.
    .tint(globalSettings.customAccentColor ?? .accentColor)
  }
}

// MARK: - View Components

extension AboutView {

  private var appIconView: some View {
    Group {
      #if os(iOS)
        if let appIcon = UIApplication.shared.currentAppIcon {
          Image(uiImage: appIcon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
            .cornerRadius(20)
            // Non-interactive; the picker lives in Settings now.
            .accessibilityLabel(Text("Blankie app icon"))
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

  // One style up on macOS, like the rest of the About type roles.
  #if os(macOS)
    private static let nameStyle: Font.TextStyle = .title
  #else
    private static let nameStyle: Font.TextStyle = .title2
  #endif

  private var appInfoSection: some View {
    VStack(spacing: 8) {
      Text(verbatim: "Blankie")
        .font(.system(Self.nameStyle, design: .rounded).weight(.medium))

      Text(LocalizedStringKey("Version \(appVersion) (\(buildNumber))"))
        .font(.aboutCaption)
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
        // .tint (not the default link blue) so links follow the app accent.
        Link("blankie.rest", destination: URL(string: "https://blankie.rest")!)
          .foregroundStyle(.tint)
          .handCursor()
      }

      Link(destination: URL(string: "https://github.com/codybrom/blankie")!) {
        HStack(spacing: 4) {
          Image(systemName: "star.fill").foregroundStyle(.yellow)
          Text("Star on GitHub")
            .foregroundStyle(.tint)
        }
      }
      .handCursor()

      Link(destination: URL(string: "https://github.com/codybrom/blankie/issues")!) {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Text("Report an Issue")
            .foregroundStyle(.tint)
        }
      }
      .handCursor()
    }
    .font(.aboutBody)
  }

  private var copyrightText: some View {
    // Single source of truth: the bundle's NSHumanReadableCopyright, localized
    // via InfoPlist.xcstrings (same value the system uses). localizedInfoDictionary
    // gives the per-language value; fall back to the base plist so en (or any
    // missing locale) still shows the copyright rather than the raw key.
    let copyright =
      (Bundle.main.localizedInfoDictionary?["NSHumanReadableCopyright"] as? String)
      ?? (Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String)
      ?? ""
    return Text(copyright)
      .font(.aboutCaption)
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
        // Two columns of credit cards on macOS — the rows are short and the
        // single column made the list a scroll marathon in the pane. Each
        // card stays one VoiceOver group (CreditRow's contained element).
        #if os(macOS)
          LazyVGrid(
            columns: [
              GridItem(.flexible(), spacing: 12, alignment: .topLeading),
              GridItem(.flexible(), spacing: 12, alignment: .topLeading),
            ],
            alignment: .leading, spacing: 12
          ) {
            ForEach(creditsManager.credits, id: \.name) { credit in
              CreditRow(credit: credit)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                  RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                )
            }
          }
        #else
          VStack(alignment: .leading, spacing: 4) {
            ForEach(creditsManager.credits, id: \.name) { credit in
              CreditRow(credit: credit)
            }
          }
        #endif
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

}

// MARK: - Data Loading

extension AboutView {
  private func loadCredits() {
    guard let url = Bundle.main.url(forResource: "credits", withExtension: "json") else {
      Logger.ui.debug("Unable to find credits.json in bundle")
      return
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let credits = try decoder.decode(Credits.self, from: data)
      contributors = credits.contributors
      betaTesters = credits.betaTesters ?? []
      translators = credits.translators
    } catch {
      Logger.ui.error("Error loading credits: \(error, privacy: .public)")
    }
  }
}

#Preview {
  AboutView()
    .modelContainer(for: [CustomSoundData.self, PresetArtwork.self])
}
