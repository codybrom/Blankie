#!/usr/bin/swift
///
/// blanki18n
/// By Cody Bromley
/// MIT License
///
/// This script is used to update the Localizable.xcstrings file with single-language translations in JSON or CSV format
/// To learn more, visit blankie.rest/i18n
///
///  Usage: ./blanki18n.swift path/to/translation.[json|csv] [language_code] [--preserve-states]
///

import Foundation

// MARK: - CSV Parser

struct CSVRow {
  let key: String
  let target: String
  let state: String
}

func parseCSV(data: String) -> [CSVRow] {
  var rows: [CSVRow] = []
  let lines = data.components(separatedBy: .newlines)

  guard !lines.isEmpty else { return rows }

  // Detect delimiter by counting occurrences in the header line
  let header = lines[0]
  let semicolonCount = header.components(separatedBy: ";").count - 1
  let commaCount = header.components(separatedBy: ",").count - 1
  let delimiter = semicolonCount > commaCount ? ";" : ","

  // Skip header
  for line in lines.dropFirst() where !line.isEmpty {
    let columns = line.components(separatedBy: delimiter)
      .map { $0.trimmingCharacters(in: .init(charactersIn: "\"")) }

    if columns.count >= 4 {
      // For semicolon CSVs, check both source (index 1) and target (index 2) columns
      // Use whichever is non-empty, preferring target if both exist
      let sourceValue = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
      let targetValue = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)
      let translation = !targetValue.isEmpty ? targetValue : sourceValue

      rows.append(
        CSVRow(
          key: columns[0],
          target: translation,
          state: columns[3]
        ))
    }
  }

  return rows
}

// MARK: - Utilities

func getFilePath() -> String {
  guard CommandLine.arguments.count > 1 else {
    print("Error: Please provide a translation file path")
    print(
      "Usage: ./blanki8n.swift path/to/translation.[json|csv] [language_code] [--preserve-states]")
    exit(1)
  }

  return CommandLine.arguments[1]
}

func getLanguageCode() -> String {
  if CommandLine.arguments.count > 2 && !CommandLine.arguments[2].starts(with: "--") {
    return CommandLine.arguments[2]
  } else {
    print("\nEnter the language code for these translations (e.g. de, es, fr):")
    guard let inputLangCode = readLine()?.trimmingCharacters(in: .whitespaces),
      !inputLangCode.isEmpty
    else {
      print("Error: Invalid language code")
      exit(1)
    }
    return inputLangCode
  }
}

func shouldPreserveStates() -> Bool {
  return CommandLine.arguments.contains("--preserve-states")
}

func parseJSON(data: Data) -> [CSVRow] {
  var rows: [CSVRow] = []

  guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let strings = json["strings"] as? [String: [String: Any]]
  else {
    return rows
  }

  for (key, value) in strings {
    if let target = value["target"] as? String,
      let state = value["state"] as? String
    {
      rows.append(CSVRow(key: key, target: target, state: state))
    }
  }

  return rows
}

func readTranslationFile(at path: String) -> [CSVRow] {
  if path.hasSuffix(".json") {
    guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
      print("Error: Could not read file at \(path)")
      exit(1)
    }
    return parseJSON(data: fileData)
  } else if path.hasSuffix(".csv") {
    // Try multiple encodings (UTF-8, Mac Central European Roman, MacRoman, Windows-1252, ISO Latin-2)
    // Mac Central European Roman is for Central/Eastern European languages like Hungarian
    let encodings: [String.Encoding] = [
      .utf8,
      String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
          CFStringEncoding(CFStringEncodings.macCentralEurRoman.rawValue))), .macOSRoman,
      .windowsCP1252, .isoLatin2,
    ]

    for encoding in encodings {
      if let fileData = try? String(contentsOfFile: path, encoding: encoding) {
        print("Successfully read file using encoding: \(encoding)")
        return parseCSV(data: fileData)
      }
    }

    print("Error: Could not read file at \(path) with any supported encoding")
    exit(1)
  } else {
    print("Error: Only CSV and JSON files are supported")
    exit(1)
  }
}

func readXCStringsFile() -> (json: [String: Any], strings: [String: [String: Any]]) {
  let xcstringsURL = URL(fileURLWithPath: "Blankie/Localizable.xcstrings")

  guard let xcstringsData = try? Data(contentsOf: xcstringsURL) else {
    print("Error: Could not read Localizable.xcstrings")
    exit(1)
  }

  guard let json = try? JSONSerialization.jsonObject(with: xcstringsData) as? [String: Any],
    let strings = json["strings"] as? [String: [String: Any]]
  else {
    print("Error: Could not parse Localizable.xcstrings")
    exit(1)
  }

  return (json: json, strings: strings)
}

func updateTranslations(
  in strings: [String: [String: Any]], with translations: [CSVRow], for langCode: String,
  preserveStates: Bool
) -> ([String: [String: Any]], Int) {
  var updatedStrings = strings
  var updatedCount = 0

  for translation in translations {
    if var entry = strings[translation.key],
      var localizations = entry["localizations"] as? [String: [String: Any]]
    {

      // Check if the translation has a meaningful value
      let targetValue = translation.target.trimmingCharacters(in: .whitespacesAndNewlines)
      let hasValidTranslation = !targetValue.isEmpty && targetValue != translation.key

      // Add or update the localization for this language
      let state: String
      if preserveStates {
        state = translation.state
      } else {
        // Default behavior: mark all valid translations as "translated"
        state = hasValidTranslation ? "translated" : "translated"
      }

      // Check if this is actually a change
      let existingLocalization = localizations[langCode]
      let existingStringUnit = existingLocalization?["stringUnit"] as? [String: Any]
      let existingValue = existingStringUnit?["value"] as? String
      let existingState = existingStringUnit?["state"] as? String

      let isChanged = existingValue != translation.target || existingState != state

      if isChanged {
        localizations[langCode] = [
          "stringUnit": [
            "state": state,
            "value": translation.target,
          ]
        ]

        // Update the entry
        entry["localizations"] = localizations
        updatedStrings[translation.key] = entry
        updatedCount += 1
      }
    }
  }

  return (updatedStrings, updatedCount)
}

func writeUpdatedStrings(
  json: [String: Any], strings: [String: [String: Any]], updatedCount: Int, langCode: String
) {
  let xcstringsURL = URL(fileURLWithPath: "Blankie/Localizable.xcstrings")
  var updatedJson = json
  updatedJson["strings"] = strings

  if let updatedData = try? JSONSerialization.data(
    withJSONObject: updatedJson, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
    let updatedString = String(data: updatedData, encoding: .utf8)
  {
    try? updatedString.write(to: xcstringsURL, atomically: true, encoding: .utf8)
    print("\nSuccess! Updated \(updatedCount) translations for language: \(langCode)")
  } else {
    print("Error: Could not write updated translations")
    exit(1)
  }
}

// MARK: - Main

func main() {
  print("blanki8n Localization Updater")
  print("===================")

  let filePath = getFilePath()
  let translations = readTranslationFile(at: filePath)
  let langCode = getLanguageCode()
  let preserveStates = shouldPreserveStates()

  if preserveStates {
    print("\nPreserving translation states from imported file")
  }

  let (json, strings) = readXCStringsFile()
  let (updatedStrings, updatedCount) = updateTranslations(
    in: strings, with: translations, for: langCode, preserveStates: preserveStates)

  if updatedCount == 0 {
    print("No translations were updated. Check if your keys match the ones in the xcstrings file.")
    exit(1)
  }

  writeUpdatedStrings(
    json: json, strings: updatedStrings, updatedCount: updatedCount, langCode: langCode)
}

main()
