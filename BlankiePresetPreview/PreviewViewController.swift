//
//  PreviewViewController.swift
//  BlankiePresetPreview
//
//  Created by Cody Bromley on 6/22/26.
//
//  Principal controller (from MainInterface.storyboard) for the Quick Look
//  preview of a `.blankie` file. Registered for com.codybrom.blankie.preset.
//

import QuickLook
import SwiftUI
import UIKit

class PreviewViewController: UIViewController, QLPreviewingController {
  func preparePreviewOfFile(at url: URL) async throws {
    // Decode off the main actor; the zip read + image decode shouldn't block UI.
    let info = try await Task.detached(priority: .userInitiated) {
      try PresetPreviewReader.read(from: url)
    }.value

    let host = UIHostingController(rootView: PresetPreviewView(preset: info))
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    host.didMove(toParent: self)
  }
}
