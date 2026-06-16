# Audio Managers

Everything audio lives in this folder. `AudioManager` (plus its focused extensions) is the playback authority, `AudioEngineManager` owns the single shared `AVAudioEngine` and its graph, `SoundPlayer` is the per-sound engine unit behind each `Sound`, `NowPlayingManager` publishes to the system transport surfaces, and `AudioSessionManager` holds the iOS session policy.

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

Four cooperating mechanisms. All of them are required.

1. **Idle the engine on full pause.** `AudioEngineManager.pauseIfIdle()` pauses hardware I/O once no registered player is rendering (preview mode and the mid-fade play-rescue keep it running). The graph stays intact and `ensureRunning()` restarts it on the next play. The audio session intentionally stays active so the system controls remain visible.
2. **Publish nothing while a pause fade renders.** `NowPlayingManager.performNowPlayingUpdate` holds all writes while `!isPlaying && engine.isRunning`, because any write in that window re-asserts "playing." `AudioManager.scheduleEngineIdlePause` does one full republish after the engine idles.
3. **Publish atomically.** Incremental updates merge all non-artwork keys into a copy of the dictionary and assign it once, so no intermediate publish carries a stale rate.
4. **Cut remote pauses instantly.** `Sound.remotePauseFadeDuration = 0`, passed by the remote command handlers via `setGlobalPlaybackState(_:pauseFadeDuration:)`. Nodes pause synchronously and the engine idles in the same runloop turn, leaving nothing for Control Center to re-derive. In-app pause keeps the normal 0.5s fade. A zero fade still pauses in place and preserves position, unlike `pause(immediate:)`, which stops.

### Tested dead ends (do not retry)

- **Publishing rate 0 at pause time**, with or without a fade: the I/O derivation overrides it and the button dances.
- **Publishing rate 1.0 during the fade** ("report what the hardware is doing"): contradicts the optimistic button flip. Still dances.
- **Shorter audible ramps**: 0.5s and 0.15s remote-pause fades both danced in Control Center. Only a zero-length cut is stable.
- **A rate-only "reassert" write after the engine idles**: not enough on its own while other writes still go out per-key.

### Future

iOS 27's NowPlaying framework (`MediaSession` / `MediaSessionRepresentable` / `MediaPlaybackSnapshot`) replaces rate-derivation with declared, typed state (`.playing()` / `.paused`) observed from an `@Observable` model. Apple's WWDC26 demo for it is an ambient-sounds engine app. Not even joking. I seriously couldn't make this up if I wanted. Sherlock who? Anyways, in iOS 27, `duration: .continuous` is also the sanctioned way to mark continuous audio that needs no scrubber. Adoption should be availability-gated; the mechanisms above remain the iOS 26 path. `MPNowPlayingSession` (iOS 16+) is not an alternative. It is `AVPlayer`-centric and publishes through the same dictionary mechanism.
