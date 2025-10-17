//
//  OnDemandResourceManager.swift
//  Blankie
//
//  Manages On-Demand Resources for animated artwork videos
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.codybrom.blankie", category: "ODR")

/// Resource download state
enum ResourceState: Equatable {
  case notDownloaded
  case downloading(progress: Double)
  case available
  case failed(Error)

  static func == (lhs: ResourceState, rhs: ResourceState) -> Bool {
    switch (lhs, rhs) {
    case (.notDownloaded, .notDownloaded):
      return true
    case let (.downloading(lhsProgress), .downloading(rhsProgress)):
      return lhsProgress == rhsProgress
    case (.available, .available):
      return true
    case (.failed, .failed):
      return true
    default:
      return false
    }
  }
}

/// Manages downloading and caching of on-demand animated artwork resources
@MainActor
final class OnDemandResourceManager: ObservableObject {
  static let shared = OnDemandResourceManager()

  /// Current state of each resource
  @Published private(set) var resourceStates: [String: ResourceState] = [:]

  #if !os(macOS)
    /// Active resource requests being managed (iOS only - macOS doesn't support ODR)
    private var activeRequests: [String: NSBundleResourceRequest] = [:]

    /// Queue for serializing ODR operations
    private let odrQueue = DispatchQueue(label: "com.codybrom.blankie.odr", qos: .userInitiated)
  #endif

  private init() {
    // Check which resources are already available
    checkAvailableResources()

    // Log migration info for users upgrading from previous version
    logger.info("OnDemandResourceManager initialized. Users upgrading from older versions may need to re-download videos due to restructured resource paths.")
  }

  // MARK: - Public API

  /// Request a video resource by its identifier (e.g., "RainLoop", "CityLoop")
  /// - Parameter resourceId: The identifier matching the ODR tag
  /// - Returns: URL to the video file if available
  func requestVideoResource(_ resourceId: String) async throws -> URL {
    // Check if already available in bundle (development/simulator/macOS)
    if let url = getLocalResourceURL(for: resourceId), FileManager.default.fileExists(atPath: url.path) {
      logger.debug("Resource \(resourceId) already available locally")
      resourceStates[resourceId] = .available
      return url
    }

    #if os(macOS)
      // macOS doesn't support ODR - if file isn't in bundle, it's not available
      logger.error("Resource \(resourceId) not found in bundle (macOS doesn't support ODR)")
      resourceStates[resourceId] = .failed(ODRError.resourceNotFound(resourceId))
      throw ODRError.resourceNotFound(resourceId)
    #else
      // iOS: Use ODR to download if not in bundle
      // Update state to downloading
      resourceStates[resourceId] = .downloading(progress: 0.0)

      // Create resource request with the tag
      let request = NSBundleResourceRequest(tags: [resourceId])

      // Store the active request
      activeRequests[resourceId] = request

      // Set up progress tracking with KVO
      request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent

      // Track progress using polling
      let progressTask = Task { @MainActor in
        while !Task.isCancelled {
          let currentProgress = request.progress.fractionCompleted
          // Update the download progress
          if case .downloading = self.resourceStates[resourceId] {
            self.resourceStates[resourceId] = .downloading(progress: currentProgress)
          } else {
            // State changed, stop tracking
            break
          }
          // Poll every 0.1 seconds
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
      }

      do {
        logger.info("Requesting ODR resource: \(resourceId)")

        // Begin accessing the resource
        try await request.beginAccessingResources()

        // Cancel progress tracking
        progressTask.cancel()

        // Resource is now available
        logger.info("Successfully downloaded ODR resource: \(resourceId)")
        resourceStates[resourceId] = .available

        // Get the URL to the downloaded resource
        guard let url = getLocalResourceURL(for: resourceId) else {
          throw ODRError.resourceNotFound(resourceId)
        }

        return url

      } catch {
        // Cancel progress tracking
        progressTask.cancel()

        logger.warning("ODR download failed for \(resourceId), checking if bundled locally: \(error.localizedDescription)")

        // ODR failed - check if the resource is bundled locally (development/simulator)
        if let url = getLocalResourceURL(for: resourceId), FileManager.default.fileExists(atPath: url.path) {
          logger.info("Resource \(resourceId) found in local bundle, using as fallback")
          resourceStates[resourceId] = .available
          activeRequests.removeValue(forKey: resourceId)
          return url
        }

        // Neither ODR nor local bundle worked
        logger.error("Resource \(resourceId) not available via ODR or local bundle")
        resourceStates[resourceId] = .failed(error)
        activeRequests.removeValue(forKey: resourceId)
        throw ODRError.downloadFailed(resourceId, error)
      }
    #endif
  }

  /// Preload multiple resources in the background
  /// - Parameter resourceIds: Array of resource identifiers to preload
  func preloadResources(_ resourceIds: [String]) async {
    logger.info("Preloading \(resourceIds.count) ODR resources")

    await withTaskGroup(of: Void.self) { group in
      for resourceId in resourceIds {
        group.addTask {
          do {
            _ = try await self.requestVideoResource(resourceId)
          } catch {
            logger.error("Failed to preload resource \(resourceId): \(error.localizedDescription)")
          }
        }
      }
    }
  }

  /// Release a resource to free up disk space
  /// - Parameter resourceId: The identifier of the resource to release
  func releaseResource(_ resourceId: String) {
    #if !os(macOS)
      guard let request = activeRequests[resourceId] else { return }

      logger.info("Releasing ODR resource: \(resourceId)")
      request.endAccessingResources()
      activeRequests.removeValue(forKey: resourceId)
      resourceStates[resourceId] = .notDownloaded
    #else
      // macOS doesn't use ODR, so nothing to release
      logger.debug("Release resource called on macOS (no-op)")
    #endif
  }

  /// Release all resources
  func releaseAllResources() {
    #if !os(macOS)
      logger.info("Releasing all ODR resources (\(self.activeRequests.count) active)")

      for (resourceId, request) in self.activeRequests {
        request.endAccessingResources()
        self.resourceStates[resourceId] = .notDownloaded
      }

      self.activeRequests.removeAll()
    #else
      // macOS doesn't use ODR, so nothing to release
      logger.debug("Release all resources called on macOS (no-op)")
    #endif
  }

  /// Check if a resource is currently available locally in ODR storage
  /// - Parameter resourceId: The resource identifier
  /// - Returns: True if the resource is available in ODR cache without needing to download
  func isResourceAvailable(_ resourceId: String) -> Bool {
    guard let url = getLocalResourceURL(for: resourceId) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  /// Get the current state of a resource
  /// - Parameter resourceId: The resource identifier
  /// - Returns: The current state of the resource
  func getResourceState(_ resourceId: String) -> ResourceState {
    // First check if we have a tracked state
    if let state = resourceStates[resourceId] {
      // Verify the state is accurate - if it says available, double-check the file exists
      if case .available = state {
        if isResourceAvailable(resourceId) {
          return .available
        } else {
          // File was deleted externally, update state
          resourceStates[resourceId] = .notDownloaded
          return .notDownloaded
        }
      }
      return state
    }

    // No tracked state, check if resource is available
    if isResourceAvailable(resourceId) {
      resourceStates[resourceId] = .available
      return .available
    }

    return .notDownloaded
  }

  // MARK: - Private Helpers

  private func getLocalResourceURL(for resourceId: String) -> URL? {
    // Files are copied flat to bundle root with unique names
    return Bundle.main.url(forResource: resourceId, withExtension: "mov")
  }

  private func checkAvailableResources() {
    // Files are copied flat to bundle root, scan for metadata files
    guard let resourceURL = Bundle.main.resourceURL else {
      logger.warning("Failed to find bundle resource directory")
      return
    }

    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: resourceURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      logger.warning("Failed to read bundle resource contents")
      return
    }

    // Find all *Metadata.json files to discover resource IDs
    let metadataFiles = contents.filter { $0.lastPathComponent.hasSuffix("Metadata.json") }

    // Check which resources are already available
    var availableCount = 0
    for metadataURL in metadataFiles {
      // Extract resource ID from filename (e.g., "RainLoopMetadata.json" -> "RainLoop")
      let filename = metadataURL.deletingPathExtension().lastPathComponent
      guard let artworkId = filename.components(separatedBy: "Metadata").first else {
        continue
      }

      if isResourceAvailable(artworkId) {
        resourceStates[artworkId] = .available
        availableCount += 1
      } else {
        resourceStates[artworkId] = .notDownloaded
      }
    }

    logger.info("Found \(availableCount) available ODR resources")
  }
}

// MARK: - Errors

enum ODRError: LocalizedError {
  case resourceNotFound(String)
  case downloadFailed(String, Error)

  var errorDescription: String? {
    switch self {
    case let .resourceNotFound(id):
      return "Resource not found: \(id)"
    case let .downloadFailed(id, error):
      return "Failed to download \(id): \(error.localizedDescription)"
    }
  }
}

// MARK: - Supporting Types

// (No additional types needed - artwork discovery is dynamic)
