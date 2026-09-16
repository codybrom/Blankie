# Audio Managers

Everything audio lives in this folder. `AudioManager` (plus its focused extensions) is the playback authority, `AudioEngineManager` owns the single shared `AVAudioEngine` and its graph, `SoundPlayer` is the per-sound engine unit behind each `Sound`, the Now Playing backend behind `NowPlayingPublishing` publishes to the system transport surfaces, and `AudioSessionManager` holds the iOS session policy.

## Now Playing system behavior (iOS)

The system transport button (Control Center, Lock Screen, CarPlay, AirPods) does not simply display the playback rate an app publishes through `MPNowPlayingInfoCenter`. iOS also re-derives "playing" from live `AVAudioEngine` hardware I/O and overrides the published rate when the two disagree. On iOS 26 (June 2026) that caused two bugs here:

- **Stuck button**: after a remote pause, the engine kept running (rendering silence), so iOS kept reporting the app as playing. Every press sent `pause`, a no-op, and play appeared dead until the engine's auto-shutdown idled the hardware minutes later.
- **Icon dance**: during a pause fade-out, the button flicked pause→play→pause as the optimistic system flip, the app's publishes, and the I/O-derived override fought each other.

Everything below was established on a physical device. None of it is documented by Apple for iOS 26.

### What the system does

1. **Published rate is advisory, not authoritative.** While the engine drives hardware I/O, even rendering pure silence, iOS overrides a published `MPNowPlayingInfoPropertyPlaybackRate = 0` back to "playing."
2. **The transport button flips optimistically** the moment the user taps it, before any app response.
3. **Control Center re-derives fastest.** It caught a 0.15s fade tail that Lock Screen, CarPlay, and AirPods did not. Any audible ramp after a remote pause makes its button dance.
4. **Every write to `nowPlayingInfo` is a full publish.** An in-place key update (`center.nowPlayingInfo?[key] = …`) is a get-mutate-set of the whole dictionary, so a sequence of per-key writes publishes intermediate states, and the early ones carry the stale playback rate.
5. **`MPNowPlayingInfoCenter.playbackState` is macOS-only.** On iOS 26 an engine-based app has no sanctioned way to declare "paused" while its audio session is active.

### How Blankie stays in sync

Four cooperating mechanisms. All of them are required. Mechanisms 2 and 3 are the MediaPlayer backend's (`NowPlayingManager`) answer to rate derivation and per-key publishing, and apply only below OS 27; 1 and 4 are engine concerns that both backends rely on.

1. **Idle the engine on full pause.** `AudioEngineManager.pauseIfIdle()` pauses hardware I/O once no registered player is rendering (preview mode and the mid-fade play-rescue keep it running). The graph stays intact and `ensureRunning()` restarts it on the next play. The audio session intentionally stays active so the system controls remain visible.
2. **Publish nothing while a pause fade renders.** `NowPlayingManager.performNowPlayingUpdate` holds all writes while `!isPlaying && engine.isRunning`, because any write in that window re-asserts "playing." `AudioManager.scheduleEngineIdlePause` does one full republish after the engine idles.
3. **Publish atomically.** Incremental updates merge all non-artwork keys into a copy of the dictionary and assign it once, so no intermediate publish carries a stale rate.
4. **Cut remote pauses instantly.** `Sound.remotePauseFadeDuration = 0`, passed by the remote command handlers via `setGlobalPlaybackState(_:pauseFadeDuration:)`. Nodes pause synchronously and the engine idles in the same runloop turn, leaving nothing for Control Center to re-derive. In-app pause keeps the normal 0.5s fade. A zero fade still pauses in place and preserves position, unlike `pause(immediate:)`, which stops.

### Tested dead ends (do not retry)

- **Publishing rate 0 at pause time**, with or without a fade: the I/O derivation overrides it and the button dances.
- **Publishing rate 1.0 during the fade** ("report what the hardware is doing"): contradicts the optimistic button flip. Still dances.
- **Shorter audible ramps**: 0.5s and 0.15s remote-pause fades both danced in Control Center. Only a zero-length cut is stable.
- **A rate-only "reassert" write after the engine idles**: not enough on its own while other writes still go out per-key.

## Now Playing on OS 27

OS 27's NowPlaying framework replaces rate derivation with declared, typed state read from an `@Observable` model, so none of the mechanisms above are needed there. Both paths ship: the deployment targets stay on iOS 26.4 / macOS 26, and the 26 backend is unchanged. (`MPNowPlayingSession`, iOS 16+, is not an alternative: it is `AVPlayer`-centric and publishes through the same dictionary mechanism.)

### The shape

`NowPlayingPublishing` is the surface `AudioManager` publishes through, so no call site knows which backend it holds.

- `NowPlayingManager` (with `+RemoteCommands`, `+Artwork`, `+AnimatedArtwork`, `+Helpers`) is the MediaPlayer backend, used below 27.
- `MediaSessionNowPlaying` (with `+Artwork`) is the NowPlaying-framework backend, used on 27 and later. It resolves what to show, writes it to `NowPlayingSessionModel` — the `@Observable` `MediaSessionRepresentable` the framework reads — and keeps one `MediaSession` published.
- `NowPlayingDisplay` holds the display rules both backends share: title and subtitle, the sound-name summary, the drawn fallback images, and the animated-artwork gate. `NowPlayingSessionMapping` holds the 27 path's pure mappings (content ids, artwork ids, playback, sleep-timer timing, ratio selection) with no framework import, so they compile and are tested without the 27 SDK. `AnimatedArtworkResolver` resolves a preset's loop video and preview on iOS for both backends.
- `AudioManager.init` picks the backend on the main actor under `#available` and logs the choice through `Logger.nowPlaying` ("Now Playing backend is MediaSession" / "… is MediaPlayer").

Apple documents that using `MPNowPlayingInfoCenter` or `MPRemoteCommandCenter` alongside the NowPlaying framework for local playback is undefined behavior. The 27 backend therefore calls neither: remote commands are declared per backend, and even the aspect-ratio probe in `AnimatedArtworkKey.preferredForDevice` asks whichever framework owns the card — `AnimatedArtwork.compatibleAspectRatios` on 27, `MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys` below it.

### Session lifetime

The `MediaSession` is built on the first publish while playing, then `requestToBecomeApplicationPrimary()`. Creation alone publishes nothing, so the request is deliberately deferred until playback has started: every play path has run `setupAudioSessionForPlayback()` by then, which is the ordering Apple asks for, and it keeps the backend from ever activating or reconfiguring the audio session itself — an exclusive activation at first publish would interrupt other apps' audio on a paused launch. A failed request drops the session so the next playing publish retries. The session survives pausing; only `clear()` drops it, and the next playing publish rebuilds it. `requestToBecomeSystemPrimary()` is deliberately not used: Apple documents it as not required for local playback unless an app needs to take over as the system primary from another session, it has to be made in the foreground, and it is iOS-only (`@available(macOS, unavailable)`). Blankie never takes over another app's session, so it stays unused.

### Declared state

`MediaPlaybackSnapshot` carries `.playing()` or `.paused`; the state is declared, not inferred from hardware I/O. Duration is `MediaDuration.continuous` for an ambient mix and `.finite` only while a sleep timer runs, where the snapshot also carries `elapsedTime` and `timestamp` captured at the same instant so the system extrapolates between publishes. Timer changes arrive through `Observations` on `isTimerActive` and `selectedDuration`, not a poll. There is no loop progress on 27 by decision: `updateProgress` is a no-op and only the sleep timer moves the scrubber. While a sleep timer runs the id carries a `:timed` suffix: the system reads an item's duration once per id, so the timed card has to arrive as a new item for the finite length (and the scrubber) to appear, and it reverts when the timer ends.

### Artwork, entities, commands

The system pulls artwork through the `Artwork(id:)` and `AnimatedArtwork(id:)` providers on its own schedule and caches by id, never asking for a cached id again. `NowPlayingSessionMapping.artworkID` therefore encodes everything that changes the rendered image: the source (stored, cached file, bundled, soloed sound, drawn fallback) plus the accent color and the icons a montage fallback draws. Rebuilds are gated on the preset or soloed sound actually changing, because re-assigning artwork restarts the animated loop. The providers are `@Sendable` and capture only `Data` and `URL`.

Animated artwork is declared per aspect ratio: the ratios this device reports through `AnimatedArtwork.compatibleAspectRatios`, intersected with the ones we have both a video and a preview for. As on 26, only the preferred crop is downloaded (`downloadIfMissing: key == preferredForDevice`); the other is published only when it is already local, and a pack still downloading leaves the current card alone until `onDownloaded` comes back. The user's setting, Reduce Motion and Low Power Mode gate it exactly as on 26.

`GenericContent.appEntityIdentifiers` — from the `_NowPlaying_AppIntents` cross-import overlay, which is why those files `import AppIntents` beside `import NowPlaying` — points the card at `SoundEntity` while soloing and `PresetEntity` otherwise. Quick Mix is not a preset and points at nothing. Commands are `MediaCommand`s on the model: play, pause, togglePlayPause, and next/previous `.enabled(navigationEnabled)`, fed by `AudioManager.canNavigateNextPrevious`.

### Two guards, both needed

Every 27-only file is wrapped whole in `#if canImport(NowPlaying)`, because no generally available CI runner ships the 27 SDK (a file that also serves 26, like `BlankieAnimatedArtwork.swift`, guards just its import and its use sites). Use sites add `if #available(iOS 27, macOS 27, visionOS 27, *)`, because the deployment target stays on 26 and the choice is a runtime one. Files with no framework import — the protocol, the mappings, the shared display rules — stay unconditional. Linking needs nothing: NowPlaying weak-links automatically.

Weak linking has a cost. On an OS without NowPlaying.framework the symbols resolve to null, and a stored property whose type is a framework struct makes the enclosing type's metadata crash whenever something realizes every Objective-C class (XCTest does at startup). So no framework struct is ever stored: `NowPlayingSessionModel` keeps `artwork` and `animatedArtwork` in type-erased `Any?` boxes behind computed accessors, everything else is stored as Blankie's own value types (`SessionPlayback`, `SessionTimer`, `SessionAspectRatio`), and framework values are built inside computed properties or local scope. A class reference such as `MediaSession<Model>?` is a plain pointer and is safe.

The widget extension never compiles the 27 backend — `MediaSession` is unavailable in app extensions — so the backend choice is also behind `!WIDGET_EXTENSION` and the widget always gets `NowPlayingManager`.

### What the 27 path drops

The fade hold, the atomic dictionary merge, the rate reassert after `pauseIfIdle`, and the 0.25 s progress timer are all MediaPlayer-backend answers to rate derivation and per-key publishing; none of them exists on 27. `AudioEngineManager.pauseIfIdle()` itself stays. Idling the hardware once nothing renders is an engine concern, not a Now Playing one.

### Verification

iOS 27 was exercised on the `iPhone 18 Pro` simulator (the backend log line, clean publishes) and in the test suite. macOS 27 is compile-verified only: the host runs macOS 26.6.2, so the 26 path is what executes there. The iOS 26 runtime check still needs an iOS 26 simulator runtime or a device. On hardware, check the Lock Screen, Control Center, AirPods and CarPlay Simulator transports; that animated artwork comes up tall on iPhone and square on iPad; and the value of `AnimatedArtwork.compatibleAspectRatios`.
