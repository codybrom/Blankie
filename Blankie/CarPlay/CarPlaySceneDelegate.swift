//
// CarPlaySceneDelegate.swift
// Blankie
//
// Created by Cody Bromley on 4/18/25.
//

import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import Foundation
  import SwiftData

  class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private weak var templateScene: CPTemplateApplicationScene?

    override init() {
      super.init()
      Logger.carPlay.debug("CarPlaySceneDelegate: init")
    }

    func templateApplicationScene(
      _ scene: CPTemplateApplicationScene,
      didConnect interfaceController: CPInterfaceController
    ) {
      Logger.carPlay.debug("CarPlay: Scene delegate didConnect called!")
      self.interfaceController = interfaceController
      templateScene = scene
      applyCarContentStyle(scene.contentStyle)

      // Covers CarPlay connects the route-change observer can miss.
      Task { @MainActor in
        SpatialSessionManager.shared.endSessionForCarAudio()
      }

      // Set up CarPlay interface - the shared controller handles initialization
      CarPlayInterfaceController.shared.setInterfaceController(interfaceController)
    }

    func templateApplicationScene(
      _ scene: CPTemplateApplicationScene,
      didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
      Logger.carPlay.debug("CarPlay: Disconnected!")
      self.interfaceController = nil
      templateScene = nil
      CarPlayInterfaceController.shared.disconnect()
    }

    func contentStyleDidChange(_ contentStyle: UIUserInterfaceStyle) {
      applyCarContentStyle(contentStyle)
    }

    /// The app-wide Info.plist dark lock reaches the CarPlay scene too; pin the
    /// scene's window to the car's own light/dark so CarPlay follows the car.
    private func applyCarContentStyle(_ style: UIUserInterfaceStyle) {
      Logger.carPlay.debug("CarPlay: Applying car content style \(style.rawValue)")
      templateScene?.carWindow.overrideUserInterfaceStyle = style
    }
  }

#endif
