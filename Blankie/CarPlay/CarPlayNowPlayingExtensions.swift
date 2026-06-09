//
//  CarPlayNowPlayingExtensions.swift
//  Blankie
//
//  Created by Cody Bromley on 9/20/25.
//

// `canImport(CarPlay)` keeps this out of the macOS build: CarPlay ships only on
// iOS, so even when CARPLAY_ENABLED is defined the `import CarPlay` must not be
// parsed where the framework doesn't exist.
import os

#if CARPLAY_ENABLED && canImport(CarPlay)

  import CarPlay
  import MediaPlayer
  import SwiftUI

  extension CarPlayInterfaceController {
    /// Setup the Now Playing template with edit functionality (only when not in solo mode)
    @MainActor
    func setupNowPlayingTemplate() {
      let nowPlayingTemplate = CPNowPlayingTemplate.shared

      // Global sleep-timer entry point. Idle = plain `timer`; running = a custom
      // "timer with a clock badge" (no such SF Symbol) mirroring globe.badge.clock.
      let timerImage =
        TimerManager.shared.isTimerActive
        ? Self.timerBadgeClockImage()
        : UIImage(systemName: "timer")!
      let timerButton = CPNowPlayingImageButton(image: timerImage) { [weak self] _ in
        Task { @MainActor in
          self?.showTimerOptions()
        }
      }

      // Make the album/artist string a button that opens the timer picker.
      nowPlayingTemplate.isAlbumArtistButtonEnabled = true

      // Favorite + edit buttons show only when a preset is playing. This already
      // excludes Quick Mix — entering it clears `currentPreset` — and solo mode.
      // Quick Mix has its own CarPlay tab and isn't favoritable.
      if AudioManager.shared.soloModeSound == nil, let preset = PresetManager.shared.currentPreset {
        let favoriteToken =
          preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
        let isFavorite = GlobalSettings.shared.isStarred(favoriteToken)
        let favoriteButton = CPNowPlayingImageButton(
          image: UIImage(systemName: isFavorite ? "star.fill" : "star")!
        ) { [weak self] _ in
          Task { @MainActor in
            GlobalSettings.shared.toggleStarred(favoriteToken)
            self?.updateNowPlayingButtons()
          }
        }

        let editButton = CPNowPlayingImageButton(image: UIImage(systemName: "slider.horizontal.3")!)
        { [weak self] _ in
          Task { @MainActor in
            self?.showEditSoundsInterface()
          }
        }

        nowPlayingTemplate.updateNowPlayingButtons([favoriteButton, timerButton, editButton])
        Logger.carPlay.debug(
          "CarPlay: Now Playing configured with favorite + timer + edit buttons (preset mode)")
      } else {
        // Solo mode or Quick Mix: only the global timer button applies.
        nowPlayingTemplate.updateNowPlayingButtons([timerButton])
        Logger.carPlay.debug(
          "CarPlay: Now Playing configured with timer button only (solo / Quick Mix)")
      }
    }

    /// Update Now Playing buttons based on current playback state
    @MainActor
    func updateNowPlayingButtons() {
      setupNowPlayingTemplate()
    }

    // MARK: - Timer

    /// Push the timer duration picker onto the Now Playing screen.
    @MainActor
    func showTimerOptions() {
      guard let interfaceController = currentInterfaceController else { return }
      let template = TimerOptionsTemplate.createTemplate()
      currentTimerTemplate = template
      interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    /// Pop the timer picker after a duration is chosen or the timer is canceled.
    @MainActor
    func popTimerOptions() {
      guard let interfaceController = currentInterfaceController else { return }
      currentTimerTemplate = nil
      interfaceController.popTemplate(animated: true, completion: nil)
    }

    /// Composes a "timer with a clock badge" glyph (SF Symbols has no
    /// timer.badge.clock), mirroring globe.badge.clock. The clear knockout ring
    /// keeps the badge readable after CarPlay's monochrome retint.
    private static func timerBadgeClockImage() -> UIImage {
      let side: CGFloat = 64
      let format = UIGraphicsImageRendererFormat.preferred()
      format.opaque = false
      let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: side, height: side), format: format)

      return renderer.image { context in
        func draw(_ name: String, in rect: CGRect, pointSize: CGFloat) {
          let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
          guard
            let symbol = UIImage(systemName: name, withConfiguration: config)?
              .withTintColor(.label, renderingMode: .alwaysOriginal)
          else { return }
          let size = symbol.size
          let scale = min(rect.width / size.width, rect.height / size.height)
          let fitted = CGSize(width: size.width * scale, height: size.height * scale)
          symbol.draw(
            in: CGRect(
              x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
              width: fitted.width, height: fitted.height))
        }

        // Base timer fills the canvas.
        draw("timer", in: CGRect(x: 0, y: 0, width: side, height: side), pointSize: side * 0.7)

        // Clock badge in the bottom-trailing corner, ringed by a clear knockout.
        let badge = side * 0.46
        let badgeRect = CGRect(x: side - badge, y: side - badge, width: badge, height: badge)
        context.cgContext.setBlendMode(.clear)
        context.cgContext.fillEllipse(in: badgeRect.insetBy(dx: -side * 0.04, dy: -side * 0.04))
        context.cgContext.setBlendMode(.normal)
        draw("clock.fill", in: badgeRect, pointSize: badge)
      }
    }
  }

#endif
