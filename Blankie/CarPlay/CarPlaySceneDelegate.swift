//
// CarPlaySceneDelegate.swift
// Blankie
//
// Created by Cody Bromley on 4/18/25.
//

#if CARPLAY_ENABLED

  import CarPlay
  import Foundation
  import SwiftData

  class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    override init() {
      super.init()
      print("🚗 CarPlaySceneDelegate: INIT CALLED!")
    }

    func templateApplicationScene(
      _ scene: CPTemplateApplicationScene,
      didConnect interfaceController: CPInterfaceController
    ) {
      print("🚗 CarPlay: Scene delegate didConnect called!")
      self.interfaceController = interfaceController

      // Set up CarPlay interface - the shared controller handles initialization
      CarPlayInterfaceController.shared.setInterfaceController(interfaceController)
    }

    func templateApplicationScene(
      _ scene: CPTemplateApplicationScene,
      didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
      print("🚗 CarPlay: Disconnected!")
      self.interfaceController = nil
      CarPlayInterfaceController.shared.disconnect()
    }
  }

#endif
