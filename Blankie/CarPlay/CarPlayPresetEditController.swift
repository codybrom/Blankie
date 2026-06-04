//
//  CarPlayPresetEditController.swift
//  Blankie
//
//  Created by Cody Bromley on 12/21/24.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import SwiftUI

  extension CarPlayInterfaceController {
    // MARK: - Edit Interface Navigation

    /// Show the edit sounds interface
    @MainActor
    func showEditSoundsInterface() {
      guard let interfaceController = currentInterfaceController else { return }

      // Create the sounds editing template using PresetEditTemplate
      let editTemplate = PresetEditTemplate.createTemplate()

      // Store reference to current edit template
      currentEditTemplate = editTemplate

      // Push the edit template
      interfaceController.pushTemplate(editTemplate, animated: true) { success, error in
        if success {
          debugLog("✅ CarPlay: Successfully showed edit sounds interface")
        } else {
          debugLog(
            "❌ CarPlay: Failed to show edit sounds interface: \(error?.localizedDescription ?? "unknown error")"
          )
        }
      }
    }

    /// Show volume adjustment for a specific sound
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

    /// Show options to turn on a sound with volume selection
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

    /// Pop back and refresh the edit template
    @MainActor
    func popAndRefreshEditTemplate() {
      guard let interfaceController = currentInterfaceController else { return }

      interfaceController.popTemplate(animated: true) { [weak self] _, _ in
        // After popping back, update the edit template to show new values
        if let editTemplate = self?.currentEditTemplate {
          PresetEditTemplate.updateTemplate(editTemplate)
        }
      }
    }
  }

#endif
