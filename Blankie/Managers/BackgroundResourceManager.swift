//
//  BackgroundResourceManager.swift
//  Blankie
//
//  Created by Cody Bromley on 7/3/25.
//
//  Animated-artwork videos as Apple-hosted Managed Background Assets. Each
//  artwork is one asset pack named after its bundled id (e.g. "RainLoop").
//  Preview images stay bundled.
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
/// On iOS the system stores packs outside the app's containers, so
/// `removeResource(_:)` reclaims all of a video's space. On macOS every method is a no-op.
@MainActor
final class BackgroundResourceManager: ObservableObject {
  static let shared = BackgroundResourceManager()

  /// Current state of each asset pack, keyed by artwork id.
  @Published private(set) var states: [String: BackgroundResourceState] = [:]

  #if os(iOS)
    /// In-flight downloads keyed by id, so concurrent callers share one download.
    private var inFlight: [String: Task<URL, Error>] = [:]

    /// Playable URLs per pack id. `AssetPackManager.url(for:)` can hang on the main
    /// thread, so each is resolved off the main actor once and cached until removal.
    private var urlCache: [String: URL] = [:]

    /// Reachability, used only to fail fast with an offline message. A `.satisfied`
    /// path doesn't guarantee the download succeeds.
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

  /// Video path inside the asset-pack namespace. It must match the `fileSelectors` in
  /// scripts/package_animated_artwork.sh. A `<id>Square` pack (the iPad lock screen
  /// crop) shares its base clip's folder: `<id>/<id>Square.mov`.
  private nonisolated func relativeVideoPath(for id: String) -> String {
    if id.hasSuffix("Square") {
      let base = String(id.dropLast("Square".count))
      return "\(base)/\(id).mov"
    }
    return "\(id)/\(id).mov"
  }

  /// The pack id this device fetches for a bundled clip: `<id>Square` on iPad (its
  /// lock screen takes only the 1x1 key), `<id>` elsewhere. Every caller goes
  /// through this so a device downloads one variant per clip.
  nonisolated static func preferredPackID(for bundledID: String) -> String {
    #if os(iOS)
      return AnimatedArtworkKey.preferredForDevice == .square ? "\(bundledID)Square" : bundledID
    #else
      return bundledID
    #endif
  }

  // MARK: - Public API

  /// Ensures the artwork's pack is local and returns a playable URL to its video,
  /// joining any in-flight download. A pack already on disk never enters `.downloading`.
  func resourceURL(for id: String) async throws -> URL {
    #if os(iOS)
      if AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) {
        states[id] = .available
        return try await cachedURL(for: id)
      }

      guard isConnected else {
        states[id] = .failed(BackgroundResourceError.offline)
        throw BackgroundResourceError.offline
      }

      if let existing = inFlight[id] {
        return try await existing.value
      }

      let task = Task<URL, Error> { [weak self] in
        guard let self else { throw BackgroundResourceError.unavailable(id) }
        return try await self.download(id: id)
      }
      inFlight[id] = task
      // A removal can cancel this task and a newer request take its slot, so
      // only clear the entry while it's still this one.
      defer { if inFlight[id] == task { inFlight[id] = nil } }
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
      guard AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) else {
        urlCache[id] = nil
        return nil
      }
      // Cache only: this runs on the main actor, where `url(for:)` can hang. On a
      // miss, Now Playing calls `resourceURL(for:)`, which resolves and republishes.
      return urlCache[id]
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
      // Cancel first so an in-flight download can't mark the deleted pack `.available`.
      inFlight[id]?.cancel()
      inFlight[id] = nil
      do {
        try await AssetPackManager.shared.remove(assetPackWithID: id)
        states[id] = .notDownloaded
        urlCache[id] = nil
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
    // MARK: - URL resolution

    /// Resolves and caches a local pack's URL off the main actor (see `urlCache`).
    private func cachedURL(for id: String) async throws -> URL {
      if let cached = urlCache[id] { return cached }
      let path = relativeVideoPath(for: id)
      let url = try await Task.detached {
        try AssetPackManager.shared.url(for: FilePath(path))
      }.value
      urlCache[id] = url
      return url
    }

    // MARK: - Download

    private func download(id: String) async throws -> URL {
      states[id] = .downloading(progress: 0)
      // A pack the system evicted can reinstall at a different URL.
      urlCache[id] = nil

      let progressTask = Task { [weak self] in await self?.observeProgress(id: id) }
      defer { progressTask.cancel() }

      do {
        let pack = try await resolveAssetPack(id: id)
        // `requireLatestVersion:` selects the non-deprecated overload.
        try await AssetPackManager.shared.ensureLocalAvailability(
          of: pack, requireLatestVersion: false)
        states[id] = .available
        logger.info("Downloaded artwork asset pack \(id, privacy: .public)")
        return try await cachedURL(for: id)
      } catch {
        // Log the raw error. The UI gets a friendly one (offline if the network dropped).
        logger.error(
          "Failed to download artwork asset pack \(id, privacy: .public): \(error, privacy: .public)"
        )
        let friendly: BackgroundResourceError = isConnected ? .downloadFailed : .offline
        states[id] = .failed(friendly)
        throw friendly
      }
    }

    /// Forwards download progress to `states`. Only `download()` writes terminal
    /// states (it awaits `ensureLocalAvailability`), so this never does.
    private func observeProgress(id: String) async {
      for await update in AssetPackManager.shared.statusUpdates(forAssetPackWithID: id) {
        // An update can land after download() wrote the terminal state.
        guard case .downloading = states[id] else { continue }
        if case .downloading(_, let progress) = update {
          states[id] = .downloading(progress: progress.fractionCompleted)
        }
      }
    }

    /// `assetPack(withID:)` is the only id-to-pack lookup in the iOS 26 SDK. Its
    /// replacement, `AssetPackManager.manifest`, is iOS 27.
    /// - TODO(iOS 27 SDK): switch to `AssetPackManager.shared.manifest.assetPack(withID:)`.
    private func resolveAssetPack(id: String) async throws -> AssetPack {
      try await AssetPackManager.shared.assetPack(withID: id)
    }
  #endif
}

/// Errors surfaced by the background-resource manager. Messages are end-user
/// facing. The raw underlying error is logged separately for diagnostics.
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
