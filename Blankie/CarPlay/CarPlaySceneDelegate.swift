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
      CarPlayInterfaceController.shared.disconnect()
    }
  }

#endif
