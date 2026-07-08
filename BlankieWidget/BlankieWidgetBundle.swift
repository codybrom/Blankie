//
//  BlankieWidgetBundle.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import SwiftUI
import WidgetKit

@main
struct BlankieWidgetBundle: WidgetBundle {
  var body: some Widget {
    NowPlayingWidget()
    FavoritesWidget()
    PinnedItemWidget()
    QuickMixWidget()
    PlaybackControl()
    FavoriteControl()
  }
}
