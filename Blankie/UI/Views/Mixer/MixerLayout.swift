//
//  MixerLayout.swift
//  Blankie
//
//  Created by Cody Bromley on 10/24/26.
//
//  Which mixer layout the window gets. Size class decides compact vs regular;
//  on iPhone Duo's open screen the fold splits it into two pages: Now Playing
//  and the mixer side by side (fold down the middle) or stacked (fold across,
//  the nightstand layout). Flat or bent alike, so bending moves nothing.
//

import CoreGraphics

nonisolated enum MixerLayout: Equatable, Sendable {
  case compact
  case regular
  case proppedUp
  case pages

  static func resolve(isRegularWidth: Bool, fold: FoldInfo) -> MixerLayout {
    if fold.isPresent, !fold.isVerticalCrease, fold.isActive || isRegularWidth {
      return .proppedUp
    }
    guard isRegularWidth else { return .compact }
    return fold.isPresent && fold.isVerticalCrease ? .pages : .regular
  }
}
