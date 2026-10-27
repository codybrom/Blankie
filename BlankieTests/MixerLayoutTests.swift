//
//  MixerLayoutTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/24/26.
//
//  Size class picks compact vs regular. On iPhone Duo's open screen a fold
//  down the middle gives Now Playing and the mixer a page each; a fold across
//  it stacks them (the nightstand layout). Flat or bent alike, so bending the
//  device moves nothing.
//

import CoreGraphics
import Testing

@testable import Blankie

@Suite struct MixerLayoutTests {
  private let verticalCrease = CGRect(x: 455.5, y: 0, width: 40, height: 669)
  private let horizontalCrease = CGRect(x: 0, y: 456, width: 669, height: 40)

  @Test func compactWithoutFold() {
    #expect(MixerLayout.resolve(isRegularWidth: false, fold: .none) == .compact)
  }

  @Test func regularWithoutFold() {
    #expect(MixerLayout.resolve(isRegularWidth: true, fold: .none) == .regular)
  }

  @Test func flatDuoGetsFacingPages() {
    let fold = FoldInfo(frame: verticalCrease, isActive: false)
    #expect(MixerLayout.resolve(isRegularWidth: true, fold: fold) == .pages)
  }

  /// A real flat Duo reports a zero-width fold; it still lays out like book.
  @Test func zeroWidthFlatFoldGetsFacingPages() {
    let fold = FoldInfo(frame: CGRect(x: 476, y: 0, width: 0, height: 669), isActive: false)
    #expect(fold.isPresent)
    #expect(MixerLayout.resolve(isRegularWidth: true, fold: fold) == .pages)
  }

  @Test func bookFoldGetsFacingPages() {
    let fold = FoldInfo(frame: verticalCrease, isActive: true)
    #expect(MixerLayout.resolve(isRegularWidth: true, fold: fold) == .pages)
  }

  @Test func flatPortraitDuoStacksLikeTheNightstand() {
    let fold = FoldInfo(frame: horizontalCrease, isActive: false)
    #expect(MixerLayout.resolve(isRegularWidth: true, fold: fold) == .proppedUp)
  }

  /// A narrow window (Split View) that happens to hold a flat fold stays iPhone-like.
  @Test func compactWithFlatFoldStaysCompact() {
    let vertical = FoldInfo(frame: verticalCrease, isActive: false)
    let horizontal = FoldInfo(frame: horizontalCrease, isActive: false)
    #expect(MixerLayout.resolve(isRegularWidth: false, fold: vertical) == .compact)
    #expect(MixerLayout.resolve(isRegularWidth: false, fold: horizontal) == .compact)
  }

  @Test func proppedUp() {
    let fold = FoldInfo(frame: horizontalCrease, isActive: true)
    #expect(MixerLayout.resolve(isRegularWidth: true, fold: fold) == .proppedUp)
  }

  @Test func proppedUpEvenIfCompact() {
    let fold = FoldInfo(frame: horizontalCrease, isActive: true)
    #expect(MixerLayout.resolve(isRegularWidth: false, fold: fold) == .proppedUp)
  }
}
