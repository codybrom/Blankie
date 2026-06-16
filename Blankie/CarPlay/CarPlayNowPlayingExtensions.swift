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
    /// Setup the Now Playing template: a favorite button for the current solo
    /// sound or preset (plus edit for presets), and the global sleep timer.
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

      // The album line only surfaces the timer ("N Minute Timer") while one is
      // running, so make it a tappable shortcut to the timer picker only then.
      // Without a timer it shows the sound names and shouldn't act as a button.
      nowPlayingTemplate.isAlbumArtistButtonEnabled = TimerManager.shared.isTimerActive

      // A soloed sound is favoritable under its own `solo:` token, just like in
      // the picker and sidebar — show a favorite button (no edit, since there's
      // nothing to mix). Presets get favorite + edit. Quick Mix has its own
      // CarPlay tab and isn't favoritable, so it falls through to timer-only.
      if let soloSound = AudioManager.shared.soloModeSound {
        let favoriteButton = Self.favoriteButton(
          for: GlobalSettings.soloToken(forFileName: soloSound.fileName)
        ) { [weak self] in self?.updateNowPlayingButtons() }

        nowPlayingTemplate.updateNowPlayingButtons([favoriteButton, timerButton])
        Logger.carPlay.debug(
          "CarPlay: Now Playing configured with favorite + timer buttons (solo mode)")
      } else if let preset = PresetManager.shared.currentPreset {
        let favoriteToken =
          preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
        let favoriteButton = Self.favoriteButton(for: favoriteToken) {
          [weak self] in self?.updateNowPlayingButtons()
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
        // Quick Mix (no preset): only the global timer button applies.
        nowPlayingTemplate.updateNowPlayingButtons([timerButton])
        Logger.carPlay.debug(
          "CarPlay: Now Playing configured with timer button only (Quick Mix)")
      }
    }

    /// A star button that toggles the given starred token, filled while starred.
    /// `onToggle` refreshes the Now Playing buttons so the glyph updates in place.
    @MainActor
    private static func favoriteButton(
      for token: String, onToggle: @escaping @MainActor () -> Void
    ) -> CPNowPlayingImageButton {
      let isFavorite = GlobalSettings.shared.isStarred(token)
      return CPNowPlayingImageButton(
        image: UIImage(systemName: isFavorite ? "star.fill" : "star")!
      ) { _ in
        Task { @MainActor in
          GlobalSettings.shared.toggleStarred(token)
          onToggle()
        }
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
