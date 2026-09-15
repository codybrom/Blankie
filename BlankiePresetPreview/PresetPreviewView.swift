//
//  PresetPreviewView.swift
//  BlankiePresetPreview
//
//  Created by Cody Bromley on 6/22/26.
//
//  The Quick Look card shown when a `.blankie` is tapped in Messages/Files.
//  Tapping can't open the app (iOS routes a tapped document to Quick Look), so
//  this card identifies the preset and teaches the one path that does import it:
//  tap Share, then tap the Blankie icon.
//

import SwiftUI
import UIKit

struct PresetPreviewView: View {
  let preset: PresetPreviewReader.PresetInfo

  private static let backdrop = LinearGradient(
    colors: [Color(red: 0.05, green: 0.08, blue: 0.18), Color(red: 0.10, green: 0.20, blue: 0.45)],
    startPoint: .top,
    endPoint: .bottom
  )

  var body: some View {
    ZStack {
      Self.backdrop.ignoresSafeArea()
      VStack(spacing: 30) {
        Spacer(minLength: 0)
        identity
        instructionCard
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 28)
      .frame(maxWidth: 460)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Identity

  private var identity: some View {
    VStack(spacing: 14) {
      artwork
      VStack(spacing: 5) {
        Text("Blankie Preset")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.7))

        Text(preset.name)
          .font(.title.weight(.bold))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .lineLimit(2)

        Text(soundCountText)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.7))
      }
    }
  }

  @ViewBuilder private var artwork: some View {
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    Group {
      if let data = preset.artworkData, let image = UIImage(data: data) {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
      } else {
        // The app's own no-artwork treatment: a montage of the preset's sound
        // icons (or the Blankie mark) in the preset's accent, so Quick Look
        // matches what Blankie shows for the same preset.
        FallbackArtwork(
          glyph: .playback(
            isQuickMix: false, isDefaultPreset: preset.isDefault, icons: preset.iconNames),
          accent: preset.accentColorName.flatMap(Color.init(fromString:)) ?? .accentColor,
          size: 120,
          cornerRadius: 22)
      }
    }
    .frame(width: 120, height: 120)
    .clipShape(shape)
    .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
  }

  // MARK: - Instructions

  private var instructionCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Add it to Blankie")
        .font(.headline)
        .foregroundStyle(.white)

      step(number: 1, label: "Tap Share") {
        Image(systemName: "square.and.arrow.up")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
      }
      step(number: 2, label: "Tap the Blankie icon") {
        appMark
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private func step(
    number: Int, label: LocalizedStringKey, @ViewBuilder icon: () -> some View
  ) -> some View {
    HStack(spacing: 14) {
      Text("\(number)")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(.white.opacity(0.15), in: Circle())
      Text(label)
        .font(.body.weight(.medium))
        .foregroundStyle(.white)
      Spacer(minLength: 8)
      icon().frame(width: 30, height: 30)
    }
  }

  /// The actual Blankie app icon, from the SharedAssets catalog that both the
  /// app and this extension build. The display asset already carries its shape.
  /// Downsampled once to display size so this memory-constrained Quick Look
  /// extension doesn't decode the full 1024px asset for a 30pt icon (mirrors
  /// `AboutView.currentAppIcon`).
  private static let appIcon: UIImage? =
    UIImage(named: "BlankieAppIconDisplay")?
    .preparingThumbnail(of: CGSize(width: 90, height: 90))

  private var appMark: some View {
    Image(uiImage: Self.appIcon ?? UIImage())
      .resizable()
      .scaledToFit()
  }

  // Single pluralized key so the string catalog picks the right form per
  // language (e.g. Polish one/few/many), instead of a Swift singular/plural split.
  private var soundCountText: LocalizedStringKey {
    "\(preset.soundCount) sounds"
  }
}

#Preview {
  PresetPreviewView(
    preset: .init(
      name: "Coquí Calling", creator: "Cody", soundCount: 3, artworkData: nil,
      accentColorName: "teal", iconNames: ["cloud.rain", "wind", "bird"], isDefault: false))
}
