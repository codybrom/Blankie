//
//  CarPlaySoundNames.swift
//  Blankie
//
//  Created by Cody Bromley on 10/27/26.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import UIKit

  /// Sound-name lists and the Sounds tab's index sections, in the app's language.
  @MainActor
  enum CarPlaySoundNames {
    /// Comma-separated names for a row's detail text.
    static func list(_ sounds: [Sound]) -> String {
      sounds.map(\.localizedTitle).joined(separator: ", ")
    }

    /// Sounds grouped into the current language's index sections (letters, kana rows,
    /// pinyin initials, Hangul consonants) and sorted by reading. Empty sections are dropped.
    static func indexedSections(_ sounds: [Sound]) -> [(indexTitle: String, sounds: [Sound])] {
      let collation = UILocalizedIndexedCollation.current()
      var buckets = Array(repeating: [CollationItem](), count: collation.sectionTitles.count)
      for sound in sounds {
        let item = CollationItem(sound)
        buckets[collation.section(for: item, collationStringSelector: CollationItem.selector)]
          .append(item)
      }
      return zip(collation.sectionTitles, buckets).compactMap { title, items in
        items.isEmpty ? nil : (indexTitle: title, sounds: sorted(items, by: collation))
      }
    }

    private static func sorted(
      _ items: [CollationItem], by collation: UILocalizedIndexedCollation
    ) -> [Sound] {
      collation
        .sortedArray(from: items, collationStringSelector: CollationItem.selector)
        .compactMap { ($0 as? CollationItem)?.sound }
    }

    /// The collation reads names through an Objective-C selector. The name is read once.
    private final class CollationItem: NSObject {
      static let selector = #selector(getter: CollationItem.name)

      let sound: Sound
      @objc let name: String

      init(_ sound: Sound) {
        self.sound = sound
        self.name = sound.localizedTitle
      }
    }
  }

#endif
