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
    /// The active app icon (alternate or primary), downsampled for the header.
    var currentAppIcon: UIImage? {
      // 1024px display assets alias when GPU-minified to header size, so
      // downsample once with a proper filter.
      currentAppIconFullSize?.preparingThumbnail(of: CGSize(width: 360, height: 360))
        ?? currentAppIconFullSize
    }

    private var currentAppIconFullSize: UIImage? {
      // Load the matching display assets: UIImage(named:) throws on a
      // .icon-compiled name.
      if let altName = UIApplication.shared.alternateIconName {
        if let image = UIImage(named: "\(altName)Display") {
          return image
        }
        Logger.ui.debug("AboutView: Unable to load alternate icon image '\(altName)'; falling back")
      }

      if let image = UIImage(named: "BlankieAppIconDisplay") {
        return image
      }

      // A system symbol keeps the About header from appearing empty.
      return UIImage(systemName: "app.fill")
    }
  }

#endif

struct AboutView: View {
  @ObservedObject private var creditsManager = SoundCreditsManager.shared
  private let globalSettings = GlobalSettings.shared
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
        DeveloperSection()
        InspirationSection()
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
    // Tint once so icons using Color.accentColor resolve from the same
    // environment as tinted rows and can't flip to system blue.
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
            // Non-interactive; the picker lives in Settings.
            .accessibilityLabel(Text("Blankie app icon"))
        }
      #elseif os(macOS)
        if let appIcon = NSApplication.shared.applicationIconImage {
          Image(nsImage: appIcon)
            .resizable()
            .frame(width: 128, height: 128)
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

  private var copyrightText: some View {
    // NSHumanReadableCopyright, localized via InfoPlist.xcstrings. Falls back to
    // the base plist for en and any missing locale.
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
        // Two columns of short credit cards on macOS. Each card stays one
        // VoiceOver group (CreditRow's contained element).
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
