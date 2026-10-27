//
//  CarPlaySoundNames.swift
//  Blankie
//
//  Created by Cody Bromley on 10/27/26.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import UIKit

  /// Sound names as CarPlay shows them. Templates read and sort names only through
  /// here, so built-in sounds follow the app's language.
  @MainActor
  enum CarPlaySoundNames {
    static func name(of sound: Sound) -> String {
      sound.localizedTitle
    }

    /// Comma-separated names for a row's detail text.
    static func list(_ sounds: [Sound]) -> String {
      sounds.map(name).joined(separator: ", ")
    }

    /// Sounds in the current language's reading order.
    static func sorted(_ sounds: [Sound]) -> [Sound] {
      collationSorted(sounds.map(CollationItem.init))
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
        items.isEmpty ? nil : (indexTitle: title, sounds: collationSorted(items))
      }
    }

    private static func collationSorted(_ items: [CollationItem]) -> [Sound] {
      UILocalizedIndexedCollation.current()
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
        self.name = CarPlaySoundNames.name(of: sound)
      }
    }
  }

#endif
