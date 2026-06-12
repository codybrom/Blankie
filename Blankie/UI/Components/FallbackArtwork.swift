//
//  FallbackArtwork.swift
//  Blankie
//
//  Created by Cody Bromley on 6/12/25.
//
//  The shared fallback artwork used wherever a sound or preset has no real
//  artwork: an SF Symbol (or the Blankie mark) in the full accent on a dark,
//  accent-tinted card — the pre-session placeholder with a material tint. The
//  same view is rendered in-app (Now Playing sheet/bar, library rows) and
//  rasterized into `MPMediaItemArtwork` for the lock screen / CarPlay, so every
//  no-artwork state looks identical.
//

import SwiftUI

struct FallbackArtwork: View {
  /// What sits on the card.
  enum Glyph {
    case symbol(String)  // an SF Symbol — sound fallbacks, the waveform mark
    case brand  // the Blankie mark ("blankie.symbol")
    case composite([String])  // a montage of a preset's sound icons (up to 4)

    /// The fallback glyph for the live playback state, shared by the Now Playing
    /// sheet, mini bar, and lock-screen render so they always agree: Quick Mix
    /// always shows its grid icon, the default "All Blankie Sounds" (including
    /// the no-preset state) keeps the Blankie mark, and a custom preset shows a
    /// montage of its sounds (the mark when nothing is playing). Solo is handled
    /// by each caller before this.
    static func playback(isQuickMix: Bool, isDefaultPreset: Bool, icons: [String]) -> Glyph {
      if isQuickMix { return .symbol("square.grid.2x2") }
      if isDefaultPreset { return .brand }
      return icons.isEmpty ? .brand : .composite(icons)
    }
  }

  let glyph: Glyph
  var accent: Color = .accentColor
  var size: CGFloat = 512
  var cornerRadius: CGFloat = 12
  var isCircular = false
  /// Glyph diameter as a fraction of the card. ~0.4 reads like Apple's
  /// Background Sounds art; bump it for the denser Blankie mark.
  var glyphFraction: CGFloat = 0.42

  private var glyphSize: CGFloat { size * glyphFraction }

  private var shape: AnyShape {
    isCircular
      ? AnyShape(Circle())
      : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  /// A dark, accent-tinted card — the pre-session near-black tile, but tinted
  /// with the accent as a soft material gradient (darkened heavily so it stays
  /// subtle in the dark UI; the hue just warms the near-black).
  private var cardFill: LinearGradient {
    LinearGradient(
      colors: [
        accent.mix(with: .black, by: 0.50),
        accent.mix(with: .black, by: 0.64),
      ],
      startPoint: .top, endPoint: .bottom
    )
  }

  /// The glyph: the full accent on top of the dark card, like the pre-session
  /// placeholder. The card is always darker than this, so every accent reads.
  private var glyphTone: Color { accent }

  var body: some View {
    ZStack {
      cardFill
      glyphView
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var glyphView: some View {
    switch glyph {
    case .symbol(let name):
      flatSymbol(name, pointSize: glyphSize)
    case .brand:
      brandMark
    case .composite(let names):
      let icons = Array(names.prefix(4))
      if icons.isEmpty {
        brandMark
      } else if icons.count == 1 {
        flatSymbol(icons[0], pointSize: glyphSize)
      } else {
        compositeGrid(icons)
      }
    }
  }

  /// An SF Symbol as a flat full-accent shape on the dark card. Sized by
  /// `pointSize` so a montage cell and a full-card glyph match.
  private func flatSymbol(_ name: String, pointSize: CGFloat) -> some View {
    // Font sizing (not .resizable) preserves SF Symbols' optical centering.
    Image(systemName: name)
      .font(.system(size: pointSize, weight: .medium))
      .foregroundStyle(glyphTone)
  }

  /// Up to four sound icons in a centered 2-column montage (rows of two, a lone
  /// final icon centered), so a preset's fallback reads as *its* sounds.
  private func compositeGrid(_ icons: [String]) -> some View {
    let cell = size * 0.30
    let spacing = size * 0.09
    let rows = stride(from: 0, to: icons.count, by: 2).map {
      Array(icons[$0..<min($0 + 2, icons.count)])
    }
    return VStack(spacing: spacing) {
      ForEach(rows.indices, id: \.self) { r in
        HStack(spacing: spacing) {
          ForEach(rows[r].indices, id: \.self) { c in
            flatSymbol(rows[r][c], pointSize: cell * 0.78)
              .frame(width: cell, height: cell)
          }
        }
      }
    }
  }

  /// The Blankie mark in the full accent. Its aperture is a transparent
  /// knockout, so the dark card shows through it as a single clean dark circle
  /// against the bright mark. Palette mode (one tone) reliably punches that
  /// knockout where monochrome can leave it filled.
  private var brandMark: some View {
    Image("blankie.symbol")
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: glyphSize, height: glyphSize)
      .symbolRenderingMode(.palette)
      .foregroundStyle(glyphTone)
  }
}

#Preview {
  VStack(spacing: 24) {
    HStack(spacing: 24) {
      FallbackArtwork(glyph: .symbol("waveform"), accent: .gray, size: 160, cornerRadius: 20)
      FallbackArtwork(glyph: .symbol("fan.desk"), accent: .pink, size: 160, cornerRadius: 20)
    }
    HStack(spacing: 24) {
      FallbackArtwork(glyph: .brand, accent: .blue, size: 160, cornerRadius: 20, glyphFraction: 0.5)
      FallbackArtwork(
        glyph: .composite(["fan.desk", "airplane", "waveform", "washer.fill"]),
        accent: .teal, size: 160, cornerRadius: 20)
    }
    HStack(spacing: 24) {
      FallbackArtwork(
        glyph: .composite(["fan.desk", "airplane"]), accent: .green, size: 160, cornerRadius: 20)
      FallbackArtwork(
        glyph: .composite(["fan.desk", "airplane", "waveform"]), accent: .purple, size: 160,
        cornerRadius: 20)
    }
  }
  .padding()
  .background(Color.black)
}
