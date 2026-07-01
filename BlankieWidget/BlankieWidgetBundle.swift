//
//  BlankieWidgetBundle.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import WidgetKit
import SwiftUI

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
