//
//  CarPlaySoundNames.swift
//  Blankie
//
//  Created by Cody Bromley on 10/27/26.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import UIKit

  /// Sound names as CarPlay shows them. Templates read names only through here, so
  /// built-in sounds follow the device language.
  @MainActor
  enum CarPlaySoundNames {
    static func name(of sound: Sound) -> String {
      sound.localizedTitle
    }

    /// Comma-separated names for a row's detail text.
    static func list(_ sounds: [Sound]) -> String {
      sounds.map(name).joined(separator: ", ")
    }

    /// Sounds grouped into the current language's index sections (letters, kana rows,
    /// pinyin initials, Hangul consonants) and sorted by reading. Empty sections are dropped.
    static func indexedSections(_ sounds: [Sound]) -> [(indexTitle: String, sounds: [Sound])] {
      let collation = UILocalizedIndexedCollation.current()
      let selector = #selector(getter: CollationItem.name)
      var buckets = Array(repeating: [CollationItem](), count: collation.sectionTitles.count)
      for sound in sounds {
        let item = CollationItem(sound: sound, name: name(of: sound))
        buckets[collation.section(for: item, collationStringSelector: selector)].append(item)
      }
      return zip(collation.sectionTitles, buckets).compactMap { title, items in
        guard !items.isEmpty else { return nil }
        let sorted = collation.sortedArray(from: items, collationStringSelector: selector)
        return (indexTitle: title, sounds: sorted.compactMap { ($0 as? CollationItem)?.sound })
      }
    }

    /// The collation reads names through an Objective-C selector.
    private final class CollationItem: NSObject {
      let sound: Sound
      @objc let name: String

      init(sound: Sound, name: String) {
        self.sound = sound
        self.name = name
      }
    }
  }

#endif
