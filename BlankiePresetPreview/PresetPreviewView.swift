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
        ZStack {
          Color.white.opacity(0.08)
          Image(systemName: "moon.stars.fill")
            .font(.system(size: 40, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
        }
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
    number: Int, label: String, @ViewBuilder icon: () -> some View
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
  /// app and this extension build. The display asset already carries its shape,
  /// so it renders as-is.
  private var appMark: some View {
    Image("BlankieAppIconDisplay")
      .resizable()
      .scaledToFit()
  }

  private var soundCountText: LocalizedStringKey {
    preset.soundCount == 1 ? "1 sound" : "\(preset.soundCount) sounds"
  }
}

#Preview {
  PresetPreviewView(
    preset: .init(name: "Coquí Calling", creator: "Cody", soundCount: 1, artworkData: nil))
}
