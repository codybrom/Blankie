//
//  StorageMaintenance.swift
//  Blankie
//
//  Created by Cody Bromley on 6/14/26.
//
//  Reclaims app-owned transient files iOS doesn't clean up for us: inbound
//  document staging (Documents/Inbox, where "Open in…" and share-sheet files
//  land) and scratch (tmp, where import sources and share activity accumulate).
//  These pile up across app versions over time. Runs once at launch.
//
//  Deliberately does NOT touch Documents/.Trash — that's the Files app's
//  "Recently Deleted" for the (file-sharing-exposed) container, owned by the
//  user and auto-purged by iOS after 30 days.
//
//  Entries newer than the age guard are left alone so a just-received import or
//  inbound file is never deleted out from under an in-progress operation.
//

#if os(iOS)
  import Foundation
  import os

  enum StorageMaintenance {
    private static let logger = Logger(subsystem: "com.codybrom.blankie", category: "Storage")

    /// Removes leftover staging in `tmp` and `Documents/Inbox` older than `maxAge`.
    static func clean(olderThan maxAge: TimeInterval = 3600) {
      let fm = FileManager.default
      var roots = [URL(fileURLWithPath: NSTemporaryDirectory())]
      if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
        roots.append(docs.appendingPathComponent("Inbox", isDirectory: true))
      }

      let cutoff = Date(timeIntervalSinceNow: -maxAge)
      var removed = 0
      for root in roots {
        guard
          let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
        else { continue }
        for entry in entries {
          let modified =
            (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
          guard modified < cutoff else { continue }
          do {
            try fm.removeItem(at: entry)
            removed += 1
          } catch {
            logger.error(
              "StorageMaintenance: couldn't remove \(entry.lastPathComponent, privacy: .public): \(error, privacy: .public)"
            )
          }
        }
      }
      if removed > 0 {
        logger.debug("StorageMaintenance: removed \(removed) stale staging item(s)")
      }
    }
  }
#endif
