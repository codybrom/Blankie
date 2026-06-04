//
// CarPlaySceneDelegate.swift
// Blankie
//
// Created by Cody Bromley on 4/18/25.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import Foundation
  import SwiftData

  class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    override init() {
      super.init()
      debugLog("CarPlaySceneDelegate: init", .carPlay)
    }

    func templateApplicationScene(
      _ scene: CPTemplateApplicationScene,
      didConnect interfaceController: CPInterfaceController
    ) {
      debugLog("CarPlay: Scene delegate didConnect called!", .carPlay)
      self.interfaceController = interfaceController

      // Set up CarPlay interface - the shared controller handles initialization
      CarPlayInterfaceController.shared.setInterfaceController(interfaceController)
    }

    func templateApplicationScene(
      _ scene: CPTemplateApplicationScene,
      didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
      debugLog("CarPlay: Disconnected!", .carPlay)
      self.interfaceController = nil
      CarPlayInterfaceController.shared.disconnect()
    }
  }

#endif
