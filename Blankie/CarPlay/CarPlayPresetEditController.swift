//
//  CarPlayPresetEditController.swift
//  Blankie
//
//  Created by Cody Bromley on 12/21/24.
//

import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  extension CarPlayInterfaceController {
    // MARK: - Edit Interface Navigation

    @MainActor
    func showEditSoundsInterface() {
      guard let interfaceController = currentInterfaceController else { return }

      let editTemplate = PresetEditTemplate.createTemplate()

      currentEditTemplate = editTemplate
      currentEditPresetID = PresetManager.shared.currentPreset?.id

      interfaceController.pushTemplate(editTemplate, animated: true) { success, error in
        if success {
          Logger.carPlay.debug("CarPlay: Successfully showed edit sounds interface")
        } else {
          Logger.carPlay.error(
            "CarPlay: Failed to show edit sounds interface: \(error?.localizedDescription ?? "unknown error", privacy: .public)"
          )
        }
      }
    }

    @MainActor
    func showVolumeAdjustment(for sound: Sound) {
      guard let interfaceController = currentInterfaceController else { return }

      let volumeTemplate = PresetEditTemplate.createVolumeAdjustmentTemplate(for: sound)

      interfaceController.pushTemplate(
        volumeTemplate,
        animated: true,
        completion: nil
      )
    }

    @MainActor
    func showTurnOnOptions(for sound: Sound) {
      guard let interfaceController = currentInterfaceController else { return }

      let turnOnTemplate = PresetEditTemplate.createTurnOnTemplate(for: sound)

      interfaceController.pushTemplate(
        turnOnTemplate,
        animated: true,
        completion: nil
      )
    }

    /// Whether the open edit stack still edits the live mix of the preset it was
    /// opened for. A switch, solo or Quick Mix replaces that mix.
    @MainActor
    var editStackIsLive: Bool {
      AudioManager.shared.soloModeSound == nil && !AudioManager.shared.isQuickMix
        && PresetManager.shared.currentPreset?.id == currentEditPresetID
    }

    /// Keeps an open edit stack in step with the phone. It refreshes while it's
    /// live and pops once something replaces its mix.
    @MainActor
    func refreshOrDismissEditStack() {
      guard let editTemplate = currentEditTemplate else { return }
      if editStackIsLive {
        PresetEditTemplate.updateTemplate(editTemplate)
      } else {
        dismissEditStack()
      }
    }

    /// Pops the edit template and anything pushed above it.
    @MainActor
    func dismissEditStack() {
      defer {
        currentEditTemplate = nil
        currentEditPresetID = nil
      }
      guard let editTemplate = currentEditTemplate,
        let interfaceController = currentInterfaceController,
        let index = interfaceController.templates.firstIndex(where: { $0 === editTemplate }),
        index > 0
      else { return }
      interfaceController.pop(
        to: interfaceController.templates[index - 1], animated: true, completion: nil)
    }

    @MainActor
    func popAndRefreshEditTemplate() {
      guard let interfaceController = currentInterfaceController else { return }

      interfaceController.popTemplate(animated: true) { [weak self] _, _ in
        if let editTemplate = self?.currentEditTemplate {
          PresetEditTemplate.updateTemplate(editTemplate)
        }
      }
    }
  }

#endif
