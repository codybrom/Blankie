//
//  MixerLayout.swift
//  Blankie
//
//  Created by Cody Bromley on 10/24/26.
//
//  Which mixer layout the window gets. On iPhone Duo's open screen the fold
//  splits it into Now Playing and the mixer, side by side (vertical crease) or
//  stacked (horizontal crease). Flat and bent poses resolve the same way.
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
