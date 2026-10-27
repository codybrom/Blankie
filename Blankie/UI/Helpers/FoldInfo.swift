//
//  FoldInfo.swift
//  Blankie
//
//  Created by Cody Bromley on 10/24/26.
//

import SwiftUI

/// Where the fold runs and whether it's bent. Inactive while the display is flat.
nonisolated struct FoldInfo: Equatable, Sendable {
  var frame: CGRect
  var isActive: Bool

  static let none = FoldInfo(frame: .zero, isActive: false)

  /// A real flat fold can report zero width, so any extent counts as present.
  var isPresent: Bool { frame.width > 0 || frame.height > 0 }
  var isVerticalCrease: Bool { frame.height > frame.width }
}

/// Horizontal insets that keep a two-column grid's tiles off the fold.
nonisolated enum CreaseInsets {
  /// With a vertical fold inside the grid, bent or flat, the column gap becomes
  /// the fold band and both columns stay equal width; otherwise plain margins.
  static func twoColumn(
    containerWidth: CGFloat, margin: CGFloat, spacing: CGFloat, fold: FoldInfo
  ) -> (leading: CGFloat, trailing: CGFloat, columnSpacing: CGFloat) {
    let plain = (leading: margin, trailing: margin, columnSpacing: spacing)
    let band = fold.frame
    guard fold.isVerticalCrease,
      band.minX > margin, band.maxX < containerWidth - margin
    else { return plain }

    let gap = max(spacing, band.width)
    let gapStart = band.midX - gap / 2
    let gapEnd = band.midX + gap / 2
    let columnWidth = min(gapStart - margin, containerWidth - gapEnd - margin)
    guard columnWidth > 0 else { return plain }
    return (gapStart - columnWidth, containerWidth - gapEnd - columnWidth, gap)
  }
}

nonisolated extension CreaseInsets {
  /// Trailing padding that keeps full-width content (list rows) on the leading
  /// page while a vertical fold runs through it, flat or bent; 0 otherwise.
  static func leadingPageTrailingPadding(containerWidth: CGFloat, fold: FoldInfo) -> CGFloat {
    leadingPage(containerWidth: containerWidth, fold: fold).map { containerWidth - $0 } ?? 0
  }

  /// Two side-by-side panes: split on the fold, bent or flat (leading page,
  /// band gap), otherwise down the middle.
  static func split(containerWidth: CGFloat, fold: FoldInfo) -> (leading: CGFloat, gap: CGFloat) {
    leadingPage(containerWidth: containerWidth, fold: fold).map { ($0, fold.frame.width) }
      ?? (containerWidth / 2, 0)
  }

  /// Where content starts when a fold runs close to the container's leading
  /// edge (the mixer beside the Library): past the fold, on the page the book
  /// pose gives it. nil when the fold is near the middle or absent.
  static func trailingPageStart(containerWidth: CGFloat, fold: FoldInfo) -> CGFloat? {
    guard let leading = leadingPage(containerWidth: containerWidth, fold: fold),
      leading < (containerWidth - fold.frame.maxX) / 2
    else { return nil }
    return fold.frame.maxX
  }

  /// Width of the page before a vertical fold inside the container, bent or
  /// flat, so a pane can end at the seam; nil without one.
  static func leadingPage(containerWidth: CGFloat, fold: FoldInfo) -> CGFloat? {
    fold.isVerticalCrease && fold.frame.minX > 0 && fold.frame.maxX < containerWidth
      ? fold.frame.minX : nil
  }
}

extension View {
  /// Keeps full-width content on the leading page while a fold runs through it.
  func keepsToLeadingPageWhenFolded() -> some View {
    modifier(LeadingPageWhenFolded())
  }
}

private struct LeadingPageWhenFolded: ViewModifier {
  @State private var fold = FoldInfo.none
  @State private var width: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .padding(
        .trailing, CreaseInsets.leadingPageTrailingPadding(containerWidth: width, fold: fold)
      )
      .onFoldChange { fold = $0 }
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        width = $0
      }
  }
}

extension View {
  /// Reports the fold in this view's local space as it bends; `FoldInfo.none`
  /// below iOS 27.1 and on other platforms, so callers need no availability checks.
  @ViewBuilder
  func onFoldChange(_ action: @escaping (FoldInfo) -> Void) -> some View {
    #if os(iOS)
      if #available(iOS 27.1, *) {
        onGeometryChange(for: FoldInfo.self) { proxy in
          proxy.reservedRegions(kind: .division, options: .includeInactive).first
            .map { FoldInfo(frame: $0.frame, isActive: $0.isActive) } ?? .none
        } action: { fold in
          action(fold)
        }
      } else {
        onAppear { action(.none) }
      }
    #else
      onAppear { action(.none) }
    #endif
  }
}
