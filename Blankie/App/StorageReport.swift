//
//  StorageReport.swift
//  Blankie
//
//  Created by Cody Bromley on 6/14/26.
//
//  DEBUG-only on-disk storage breakdown, logged once at launch. Settings shows a
//  single opaque "Documents & Data" number; this itemizes what Blankie actually
//  uses so a 600 MB mystery becomes legible. Not compiled into release builds.
//
//  Runs off the main thread (FileManager walks + AssetPackManager.url(for:) are
//  both flagged as main-thread hazards).
//

#if DEBUG && os(iOS)
  import BackgroundAssets
  import Foundation
  import System
  import os

  enum StorageReport {
    private static let logger = Logger(subsystem: "com.codybrom.blankie", category: "Storage")

    static func log() {
      let fm = FileManager.default
      logger.debug("──── Blankie storage report ────")

      if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
        logSize("Documents (app)", dirSize(docs))
        logChildren(of: docs)
      }
      if let container = AppGroupConfiguration.containerURL {
        logSize("App Group container", dirSize(container))
        logChildren(of: container)
      }
      if let shared = AppGroupConfiguration.documentsURL {
        logChildren(of: shared, label: "App Group/Documents")
      }
      if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
        logSize("Caches", dirSize(caches))
      }
      let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
      logSize("tmp", dirSize(tmp))
      logChildren(of: tmp)

      logBackgroundAssets()
      logger.debug(
        "Note: Background Assets packs and any leftover ODR cache live in system storage, not these containers, but Settings still bills them to Blankie."
      )
      logger.debug("────────────────────────────────")
    }

    /// Sizes the downloaded Background Assets video packs (system-managed storage).
    /// Calls `AssetPackManager` directly (its accessors are nonisolated) so this
    /// stays off the main thread.
    private static func logBackgroundAssets() {
      var total: Int64 = 0
      var ids: [String] = []
      for id in BundledAnimatedLoop.allCases.map(\.id)
      where AssetPackManager.shared.assetPackIsAvailableLocally(withID: id) {
        guard let url = try? AssetPackManager.shared.url(for: FilePath("\(id)/\(id).mov")) else {
          continue
        }
        total += fileSize(url)
        ids.append(id)
      }
      logger.debug(
        "Background Assets: \(ids.count) packs downloaded, \(human(total)) [\(ids.sorted().joined(separator: ", "))]"
      )
    }

    // MARK: - Helpers

    /// Logs each top-level child of `dir` with its size, largest first.
    private static func logChildren(of dir: URL, label: String? = nil) {
      guard
        let entries = try? FileManager.default.contentsOfDirectory(
          at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
      else { return }
      if let label { logger.debug("\(label):") }
      let sized = entries.map { (name: $0.lastPathComponent, bytes: entrySize($0)) }
        .filter { $0.bytes > 0 }
        .sorted { $0.bytes > $1.bytes }
      for entry in sized {
        logger.debug("    • \(entry.name): \(human(entry.bytes))")
      }
    }

    private static func entrySize(_ url: URL) -> Int64 {
      let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
      return isDir ? dirSize(url) : fileSize(url)
    }

    private static func dirSize(_ url: URL) -> Int64 {
      guard
        let enumerator = FileManager.default.enumerator(
          at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
      else { return 0 }
      var bytes: Int64 = 0
      for case let file as URL in enumerator {
        let values = try? file.resourceValues(forKeys: [
          .totalFileAllocatedSizeKey, .isRegularFileKey,
        ])
        if values?.isRegularFile == true { bytes += Int64(values?.totalFileAllocatedSize ?? 0) }
      }
      return bytes
    }

    private static func fileSize(_ url: URL) -> Int64 {
      Int64(
        (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize
          ?? 0)
    }

    private static func logSize(_ label: String, _ bytes: Int64) {
      logger.debug("\(label): \(human(bytes))")
    }

    private static func human(_ bytes: Int64) -> String {
      ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
  }
#endif
