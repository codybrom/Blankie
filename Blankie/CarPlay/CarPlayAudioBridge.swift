//
//  CarPlayAudioBridge.swift
//  Blankie
//

#if CARPLAY_ENABLED

  import Combine
  import Foundation

  /// Keeps `AudioManager` in sync with CarPlay connection state without the
  /// audio layer having to import or query CarPlay. Call `start()` once at app
  /// launch; the bridge subscribes to
  /// `CarPlayInterfaceController.shared.$isConnected` (the controller actually
  /// driven by `CarPlaySceneDelegate`) and pushes changes into
  /// `AudioManager.setCarPlayConnected(_:)`.
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
