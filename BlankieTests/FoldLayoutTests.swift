//
//  FoldLayoutTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/24/26.
//
//  The crease on a half-folded iPhone Duo must fall in the gap between the two
//  sound-tile columns; flat or fold-less screens keep the plain symmetric grid.
//

import CoreGraphics
import Testing

@testable import Blankie

@Suite struct FoldLayoutTests {
  private let verticalBand = CGRect(x: 456, y: 0, width: 40, height: 669)

  @Test func noneIsAbsent() {
    #expect(FoldInfo.none.isPresent == false)
    #expect(FoldInfo.none.isActive == false)
  }

  @Test func noFoldKeepsSymmetricMargins() {
    let r = CreaseInsets.twoColumn(containerWidth: 952, margin: 16, spacing: 16, fold: .none)
    #expect(r.leading == 16 && r.trailing == 16 && r.columnSpacing == 16)
  }

  // Flat or bent, nothing sits on the seam.
  @Test func flatFoldBecomesTheGapToo() {
    let flat = FoldInfo(frame: verticalBand, isActive: false)
    let r = CreaseInsets.twoColumn(containerWidth: 952, margin: 16, spacing: 16, fold: flat)
    #expect(r.columnSpacing == 40)
  }

  @Test func activeCenteredCreaseBecomesTheGap() {
    let fold = FoldInfo(frame: verticalBand, isActive: true)
    let r = CreaseInsets.twoColumn(containerWidth: 952, margin: 16, spacing: 16, fold: fold)
    #expect(r.columnSpacing == 40)
    #expect(r.leading == 16 && r.trailing == 16)
  }

  @Test func offCenterCreaseKeepsColumnsEqualAndOffTheBand() {
    let fold = FoldInfo(frame: CGRect(x: 200, y: 0, width: 40, height: 669), isActive: true)
    let r = CreaseInsets.twoColumn(containerWidth: 600, margin: 16, spacing: 16, fold: fold)
    let columnWidth = (600 - r.leading - r.trailing - r.columnSpacing) / 2
    #expect(r.leading + columnWidth <= 200)
    #expect(r.leading + columnWidth + r.columnSpacing >= 240)
    #expect(r.leading >= 16 && r.trailing >= 16)
  }

  @Test func horizontalCreaseDoesNotChangeColumns() {
    let fold = FoldInfo(frame: CGRect(x: 0, y: 456, width: 669, height: 40), isActive: true)
    let r = CreaseInsets.twoColumn(containerWidth: 669, margin: 16, spacing: 16, fold: fold)
    #expect(r.leading == 16 && r.trailing == 16 && r.columnSpacing == 16)
  }

  // Review fixes: list rows keep to the leading page; panels split on the crease.

  // Flat and bent lay out the same, so bending the device moves nothing.
  @Test func leadingPageFlatOrBent() {
    #expect(CreaseInsets.leadingPageTrailingPadding(containerWidth: 951, fold: .none) == 0)
    for active in [false, true] {
      let fold = FoldInfo(frame: verticalBand, isActive: active)
      #expect(CreaseInsets.leadingPageTrailingPadding(containerWidth: 951, fold: fold) == 495)
    }
  }

  // Beside the Library (fold near the leading edge) content moves to the far page.
  @Test func trailingPageStartsAfterANearbyFold() {
    #expect(CreaseInsets.trailingPageStart(containerWidth: 631, fold: .none) == nil)
    let centered = FoldInfo(frame: verticalBand, isActive: false)
    #expect(CreaseInsets.trailingPageStart(containerWidth: 951, fold: centered) == nil)
    let nearLeading = FoldInfo(frame: CGRect(x: 136, y: 0, width: 40, height: 669), isActive: false)
    #expect(CreaseInsets.trailingPageStart(containerWidth: 631, fold: nearLeading) == 176)
  }

  @Test func splitFollowsTheCrease() {
    let bent = FoldInfo(frame: verticalBand, isActive: true)
    let split = CreaseInsets.split(containerWidth: 951, fold: bent)
    #expect(split.leading == 456 && split.gap == 40)
    let flat = CreaseInsets.split(containerWidth: 951, fold: .none)
    #expect(flat.leading == 475.5 && flat.gap == 0)
  }

  // Panes split on the fold even when the display is flat, so nothing sits on the seam.
  @Test func splitUsesTheFoldWhileFlat() {
    let flat = FoldInfo(frame: verticalBand, isActive: false)
    let split = CreaseInsets.split(containerWidth: 951, fold: flat)
    #expect(split.leading == 456 && split.gap == 40)
  }

  @Test func leadingPageWidthFollowsAnyFold() {
    #expect(CreaseInsets.leadingPage(containerWidth: 951, fold: .none) == nil)
    let flat = FoldInfo(frame: verticalBand, isActive: false)
    #expect(CreaseInsets.leadingPage(containerWidth: 951, fold: flat) == 456)
    let horizontal = FoldInfo(frame: CGRect(x: 0, y: 456, width: 669, height: 40), isActive: true)
    #expect(CreaseInsets.leadingPage(containerWidth: 669, fold: horizontal) == nil)
  }
}
