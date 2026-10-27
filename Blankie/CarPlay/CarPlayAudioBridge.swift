//
//  CarPlayAudioBridge.swift
//  Blankie
//
//  Created by Cody Bromley on 4/21/26.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import Combine
  import Foundation

  /// Forwards `CarPlayInterfaceController.shared.$isConnected` into
  /// `AudioManager.setCarPlayConnected(_:)` so the audio layer never imports
  /// CarPlay. Call `start()` once at launch.
  @MainActor
  final class CarPlayAudioBridge {
    static let shared = CarPlayAudioBridge()

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    func start() {
      guard !started else { return }
      started = true

      CarPlayInterfaceController.shared.$isConnected
        .sink { isConnected in
          Task { @MainActor in
            AudioManager.shared.setCarPlayConnected(isConnected)
          }
        }
        .store(in: &cancellables)
    }
  }

#endif
