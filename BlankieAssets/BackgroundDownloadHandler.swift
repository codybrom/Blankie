//
//  BackgroundDownloadHandler.swift
//  BlankieAssets
//
//  Created by Cody Bromley on 6/14/26.
//

import BackgroundAssets
import ExtensionFoundation
import StoreKit

@main
struct DownloaderExtension: StoreDownloaderExtension {
  func shouldDownload(_ assetPack: AssetPack) -> Bool {
    // Return false to skip a pack the system would otherwise download automatically.
    return true
  }
}
