//
//  BackgroundResourceManager.swift
//  Blankie
//
//  Created by Cody Bromley on 7/3/25.
//
//  Manages animated-artwork videos as Apple-hosted Managed Background Assets.
//  Replaces the deprecated On-Demand Resources (NSBundleResourceRequest) path.
//
//  Each artwork is one asset pack whose ID matches the artwork's bundled
//  identifier (e.g. "RainLoop"). The pack stores a single file at the relative
//  path "<id>/<id>.mov", which is also the path passed to `url(for:)`. Preview
//  images stay bundled in the app; only the videos move to asset packs.
//

import Combine
import Foundation
import os.log

#if os(iOS)
  import BackgroundAssets
  import Network
  import System
#endif

private let logger = Logger(subsystem: "com.codybrom.blankie", category: "BackgroundResources")

/// Download/availability state for a single animated-artwork asset pack.
enum BackgroundResourceState: Equatable {
  case notDownloaded
  case downloading(progress: Double)
  case available
  case failed(Error)

  static func == (lhs: BackgroundResourceState, rhs: BackgroundResourceState) -> Bool {
    switch (lhs, rhs) {
    case (.notDownloaded, .notDownloaded): return true
    case (.downloading(let l), .downloading(let r)): return l == r
    case (.available, .available): return true
    case (.failed, .failed): return true
    default: return false
    }
  }
}

/// Downloads and serves animated-artwork videos via Background Assets.
///
/// On iOS, videos are Apple-hosted managed asset packs: the system downloads
/// them on demand and stores them outside the app's own containers, so
/// `removeResource(_:)` reclaims 100% of a video's space in one call. On macOS
/// the framework isn't adopted, so every method is a no-op / unavailable —
/// matching the prior behavior where macOS shipped no animated artwork.
@MainActor
final class BackgroundResourceManager: ObservableObject {
  static let shared = BackgroundResourceManager()

  /// Current state of each asset pack, keyed by artwork id. Views observe this.
  @Published private(set) var states: [String: BackgroundResourceState] = [:]

  #if os(iOS)
    /// In-flight `resourceURL(for:)` operations, keyed by id, so concurrent
    /// callers (gallery card + Now Playing + import) join one download instead
    /// of racing several.
    private var inFlight: [String: Task<URL, Error>] = [:]

    /// Current network reachability, so we can warn before a download instead of
    /// failing with an opaque server error. A `.satisfied` path doesn't guarantee
    /// the download succeeds, so this only short-circuits the clearly-offline
    /// case; when online we still attempt and handle failure normally.
    private let pathMonitor = NWPathMonitor()
    private var isConnected = true  // optimistic until the first path update
  #endif

  private init() {
    #if os(iOS)
      pathMonitor.pathUpdateHandler = { [weak self] path in
        let connected = path.status == .satisfied
        Task { @MainActor in self?.isConnected = connected }
      }
      pathMonitor.start(queue: DispatchQueue(label: "com.codybrom.blankie.network-monitor"))
    #endif
  }

  /// Relative path of an artwork's video inside the asset-pack namespace.
  /// Must match the `fileSelectors` path used when packaging (see
  /// scripts/package_animated_artwork.sh).
  ///
  /// Both variants of a clip live in the same folder, named after the base clip:
  /// the 3:4 portrait master is `<id>/<id>.mov`, and the 1:1 square crop (pack id
  /// `<id>Square`, used for iPad's lock screen) is `<id>/<id>Square.mov`. So a
  /// "…Square" pack maps back to its base folder rather than a folder of its own.
  private func relativeVideoPath(for id: String) -> String {
    if id.hasSuffix("Square") {
      let base = String(id.dropLast("Square".count))
      return "\(base)/\(id).mov"
    }
    return "\(id)/\(id).mov"
  }

  /// Resolves a clip's base bundled id to the asset-pack id this device should
  /// fetch: `<id>Square` on iPad (its lock screen takes only the 1x1 key), `<id>`
  /// on iPhone, and the base id unchanged where animated artwork isn't a feature.
  /// Routing every caller (gallery, prefetch, import, lock-screen publish)
  /// through this keeps a device downloading exactly one variant per clip.
  /// `nonisolated` so the synchronous prefetch mapping can call it off the main
  /// actor; it reads only a device capability, no instance state.
  nonisolated static func preferredPackID(for bundledID: String) -> String {
    #if os(iOS)
      return AnimatedArtworkKey.preferredForDevice == .square ? "\(bundledID)Square" : bundledID
    #else
      return bundledID
    #endif
  }

  // MARK: - Public API

  /// Ensures the artwork's asset pack is available locally and returns a
  /// playable URL to its video. Joins an in-flight download for the same id.
  /// Returns immediately (no `.downloading` state) when the pack is already on
  /// the device — so the UI never shows a phantom progress spinner.
  func resourceURL(for id: String) async throws -> URL {
    #if os(iOS)
      // Fast path: already on disk → mount without entering `.downloading`.
      if AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) {
        states[id] = .available
        return try AssetPackManager.shared.url(for: FilePath(relativeVideoPath(for: id)))
      }

      // A download is required. If we're clearly offline, warn now rather than
      // spinning and failing with an opaque server error.
      guard isConnected else {
        states[id] = .failed(BackgroundResourceError.offline)
        throw BackgroundResourceError.offline
      }

      if let existing = inFlight[id] {
        return try await existing.value
      }

      let task = Task<URL, Error> { [weak self] in
        guard let self else { throw BackgroundResourceError.unavailable(id) }
        defer { self.inFlight.removeValue(forKey: id) }
        return try await self.download(id: id)
      }
      inFlight[id] = task
      return try await task.value
    #else
      throw BackgroundResourceError.unavailable(id)
    #endif
  }

  /// Whether the artwork's video is already on the device (cheap, synchronous).
  func isAvailable(_ id: String) -> Bool {
    #if os(iOS)
      return AssetPackManager.shared.assetPackIsAvailableLocally(withID: id)
    #else
      return false
    #endif
  }

  /// Synchronous playable URL for an already-downloaded artwork video, or nil
  /// if the pack isn't local. For the Now Playing path, which builds artwork
  /// synchronously and triggers a download separately when this returns nil.
  func availableURL(for id: String) -> URL? {
    #if os(iOS)
      guard AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) else { return nil }
      return try? AssetPackManager.shared.url(for: FilePath(relativeVideoPath(for: id)))
    #else
      return nil
    #endif
  }

  /// Current state of an artwork, reconciled against on-disk availability.
  /// Does not mutate published state (safe to call from a view body).
  func state(for id: String) -> BackgroundResourceState {
    if let tracked = states[id] {
      if case .available = tracked, !isAvailable(id) { return .notDownloaded }
      return tracked
    }
    return isAvailable(id) ? .available : .notDownloaded
  }

  /// Removes the artwork's asset pack from the device, freeing all of its space.
  func removeResource(_ id: String) async {
    #if os(iOS)
      // Stop any in-flight download first so it can't finish and write
      // `.available` for a pack we're about to delete.
      inFlight[id]?.cancel()
      inFlight[id] = nil
      do {
        try await AssetPackManager.shared.remove(assetPackWithID: id)
        states[id] = .notDownloaded
        logger.info("Removed artwork asset pack \(id, privacy: .public)")
      } catch {
        logger.error(
          "Failed to remove artwork asset pack \(id, privacy: .public): \(error, privacy: .public)")
      }
    #endif
  }

  /// Best-effort prefetch of several artworks (e.g. next/previous presets).
  func preload(_ ids: [String]) async {
    #if os(iOS)
      await withTaskGroup(of: Void.self) { group in
        for id in ids where !AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) {
          group.addTask { [weak self] in
            _ = try? await self?.resourceURL(for: id)
          }
        }
      }
    #endif
  }

  #if os(iOS)
    // MARK: - Download

    private func download(id: String) async throws -> URL {
      states[id] = .downloading(progress: 0)

      // Mirror live download progress into `states` for the gallery UI.
      let progressTask = Task { [weak self] in await self?.observeProgress(id: id) }
      defer { progressTask.cancel() }

      do {
        let pack = try await resolveAssetPack(id: id)
        // Explicit `requireLatestVersion:` selects the non-deprecated iOS 26.4 API
        // (the bare `ensureLocalAvailability(of:)` overload is deprecated).
        try await AssetPackManager.shared.ensureLocalAvailability(
          of: pack, requireLatestVersion: false)
        states[id] = .available
        logger.info("Downloaded artwork asset pack \(id, privacy: .public)")
        return try AssetPackManager.shared.url(for: FilePath(relativeVideoPath(for: id)))
      } catch {
        // Log the raw error for diagnostics, but surface a friendly one to the
        // UI. If the network dropped mid-download, prefer the offline message.
        logger.error(
          "Failed to download artwork asset pack \(id, privacy: .public): \(error, privacy: .public)"
        )
        let friendly: BackgroundResourceError = isConnected ? .downloadFailed : .offline
        states[id] = .failed(friendly)
        throw friendly
      }
    }

    /// Mirrors live download progress into `states` for the gallery UI. Terminal
    /// states (`.available`/`.failed`) are owned solely by `download()`, which
    /// awaits the authoritative `ensureLocalAvailability` result — so this only
    /// forwards `.downloading` progress and never writes a terminal state (which
    /// would race the download's own write). The sequence ends after the system
    /// posts `.finished`/`.failed`, at which point `download()` has already set
    /// the terminal state.
    private func observeProgress(id: String) async {
      for await update in AssetPackManager.shared.statusUpdates(forAssetPackWithID: id) {
        if case .downloading(_, let progress) = update {
          states[id] = .downloading(progress: progress.fractionCompleted)
        }
      }
    }

    /// Resolves an asset-pack ID to an `AssetPack`.
    ///
    /// `assetPack(withID:)` is the only id-to-pack path in the iOS 26 SDK. Apple's
    /// docs flag it for replacement by `AssetPackManager.manifest`, but that
    /// property is iOS 27 and absent from the iOS 26 SDK, so on our 26.4 target
    /// this call ships with no deprecation warning.
    /// - TODO(iOS 27 SDK): switch to `AssetPackManager.shared.manifest.assetPack(withID:)`.
    private func resolveAssetPack(id: String) async throws -> AssetPack {
      try await AssetPackManager.shared.assetPack(withID: id)
    }
  #endif
}

/// Errors surfaced by the background-resource manager. Messages are end-user
/// facing; the raw underlying error is logged separately for diagnostics.
enum BackgroundResourceError: LocalizedError, Equatable {
  case offline
  case downloadFailed
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case .offline:
      return String(localized: "You're offline. Reconnect to download this artwork.")
    case .downloadFailed:
      return String(localized: "This artwork couldn't be downloaded. Try again later.")
    case .unavailable:
      return String(localized: "Animated artwork isn't available on this device.")
    }
  }

  /// Whether this represents a no-connection state (drives the warning UI).
  var isOffline: Bool {
    if case .offline = self { return true }
    return false
  }
}
