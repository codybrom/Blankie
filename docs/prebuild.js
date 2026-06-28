/**
 * Prebuild script to extract localization data
 * This runs automatically before building the Astro site
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";
import { globSync } from "glob";
import { execSync } from "child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Define paths
const projectRoot = path.resolve(__dirname, "..");
const outputDir = path.join(__dirname, "public", "i18n");
// Every app target that ships translatable strings. Wildcards (not a hardcoded
// "Localizable") so each target's InfoPlist.xcstrings is picked up too.
const globsPatterns = [
  path.join(projectRoot, "Blankie", "*.xcstrings"),
  path.join(projectRoot, "BlankiePresetPreview", "*.xcstrings"),
];

// Pull a { value, state } pair out of a localization node, supporting both flat
// strings and pluralized strings. Plurals are represented by their "other" form
// (the one translators edit on the site); without this they'd be dropped.
function extractUnit(localization) {
  if (!localization) return null;
  if (localization.stringUnit?.value != null) {
    return {
      value: localization.stringUnit.value,
      state: localization.stringUnit.state || "translated",
    };
  }
  const plural = localization.variations?.plural;
  if (plural) {
    const category = plural.other ? "other" : Object.keys(plural)[0];
    const unit = plural[category]?.stringUnit;
    if (unit?.value != null) {
      return { value: unit.value, state: unit.state || "translated" };
    }
  }
  return null;
}

// Ensure output directory exists
console.log(`\n✨ Prebuild: Ensuring i18n directory exists...`);
fs.mkdirSync(outputDir, { recursive: true });

// Extraction logic integrated directly
console.log(`✨ Prebuild: Extracting localization data...`);
try {
  // Find all matching files
  console.log(`Looking for files matching: ${globsPatterns.join(", ")}`);
  const files = globSync(globsPatterns);

  if (files.length === 0) {
    console.error(
      `❌ Prebuild: No files found matching: ${globsPatterns.join(", ")}`,
    );
    process.exit(1);
  }

  console.log(`Found ${files.length} file(s)`);

  // Initialize result object
  const result = {
    metadata: {
      extractedAt: new Date().toISOString(),
      tool: "blanki18n-prebuild",
      files: files,
    },
    strings: {},
  };

  // Process each file
  files.forEach((file) => {
    console.log(`Processing ${file}`);
    try {
      const content = fs.readFileSync(file, "utf8");
      const json = JSON.parse(content);

      // Extract strings and their metadata
      if (json.strings) {
        Object.keys(json.strings).forEach((key) => {
          const item = json.strings[key];

          if (item.shouldTranslate === false) {
            return; // Skip strings that shouldn't be translated
          }

          // Initialize key in result if it doesn't exist
          if (!result.strings[key]) {
            result.strings[key] = {};
          }

          // Record which catalog the string came from (first file wins). Read
          // back via the `sourceFile` key — excluded from locale enumeration.
          if (!result.strings[key].sourceFile) {
            result.strings[key].sourceFile = path.relative(projectRoot, file);
          }

          // Extract comment if available
          if (item.comment) {
            result.strings[key].comment = item.comment;
          }

          // Source (English) value + per-locale values. extractUnit handles
          // both flat strings and plurals (via their "other" form).
          const enUnit = extractUnit(item.localizations?.en);
          if (enUnit) {
            result.strings[key].en = enUnit;
          }

          if (item.localizations) {
            Object.keys(item.localizations).forEach((locale) => {
              if (locale === "en") return;
              const unit = extractUnit(item.localizations[locale]);
              if (unit) {
                result.strings[key][locale] = unit;
              }
            });
          }
        });
      }
    } catch (error) {
      console.error(`Error processing ${file}: ${error.message}`);
    }
  });

  // Create source.json with only English strings and comments
  const sourceJson = {
    metadata: {
      extractedAt: result.metadata.extractedAt,
      language: "en",
      sourceFiles: result.metadata.files,
    },
    strings: {},
  };

  // Add only English strings with comments
  Object.keys(result.strings).forEach((key) => {
    if (result.strings[key].en) {
      sourceJson.strings[key] = {
        value: result.strings[key].en.value,
        comment: result.strings[key].comment || "",
        sourceFile: result.strings[key].sourceFile || "",
      };
    }
  });

  // Save source.json
  fs.writeFileSync(
    path.join(outputDir, "source.json"),
    JSON.stringify(sourceJson, null, 2),
  );
  console.log(`Created source.json with English strings and comments`);

  // Find all languages in the data
  const languages = new Set(["en"]);
  Object.keys(result.strings).forEach((key) => {
    Object.keys(result.strings[key]).forEach((lang) => {
      if (lang !== "comment" && lang !== "context" && lang !== "sourceFile") {
        languages.add(lang);
      }
    });
  });

  console.log(
    `Found ${languages.size} languages: ${Array.from(languages).join(", ")}`,
  );

  // Create per-language files
  languages.forEach((lang) => {
    if (lang === "en") return; // Skip English as it's the source language

    const langData = {
      metadata: {
        language: lang,
        extractedAt: result.metadata.extractedAt,
        sourceFiles: result.metadata.files,
      },
      statistics: {},
      strings: {},
    };

    let totalStrings = 0;
    let translatedStrings = 0;
    let needsReviewStrings = 0;

    // Format each string for this language
    let needsTranslationStrings = 0;

    Object.keys(result.strings).forEach((key) => {
      // Only count strings that have an English source
      if (result.strings[key].en) {
        totalStrings++;

        if (result.strings[key][lang]) {
          langData.strings[key] = {
            source: result.strings[key].en.value,
            target: result.strings[key][lang].value,
            state: result.strings[key][lang].state || "translated",
            comment: result.strings[key].comment || "",
            sourceFile: result.strings[key].sourceFile || "",
          };

          if (result.strings[key][lang].state === "needs_review") {
            needsReviewStrings++;
          } else if (result.strings[key][lang].state === "translated") {
            translatedStrings++;
          } else if (
            result.strings[key][lang].state === "needs_translation" ||
            result.strings[key][lang].value === ""
          ) {
            needsTranslationStrings++;
          }
        } else {
          // Include untranslated strings with empty target
          langData.strings[key] = {
            source: result.strings[key].en.value,
            target: "",
            state: "needs_translation",
            comment: result.strings[key].comment || "",
            sourceFile: result.strings[key].sourceFile || "",
          };
          needsTranslationStrings++;
        }
      }
    });

    langData.statistics = {
      totalStrings,
      translatedStrings,
      needsReviewStrings,
      needsTranslationStrings,
      translationPercentage: totalStrings
        ? Math.round((translatedStrings / totalStrings) * 100)
        : 0,
      needsReviewPercentage: totalStrings
        ? Math.round((needsReviewStrings / totalStrings) * 100)
        : 0,
      needsTranslationPercentage: totalStrings
        ? Math.round((needsTranslationStrings / totalStrings) * 100)
        : 0,
    };

    // Save language-specific file
    const langFileName = `${lang}.json`;
    fs.writeFileSync(
      path.join(outputDir, langFileName),
      JSON.stringify(langData, null, 2),
    );
    console.log(
      `Created language file: ${langFileName} (${langData.statistics.translationPercentage}% translated, ${langData.statistics.needsReviewPercentage}% needs review)`,
    );
  });

  console.log(`\n✨ Prebuild: Generating CSV files...`);

  // Generate source CSV template
  const sourceCSV = convertSourceToCSV(sourceJson);
  fs.writeFileSync(path.join(outputDir, "source.csv"), sourceCSV);
  console.log(`Created source.csv template`);

  // Generate per-language CSV files
  languages.forEach((lang) => {
    if (lang === "en") return; // Skip English as it's the source language

    // Read the language JSON file we just created
    const langJsonPath = path.join(outputDir, `${lang}.json`);
    const langData = JSON.parse(fs.readFileSync(langJsonPath, "utf8"));

    // Convert to CSV
    const csvContent = convertTranslationToCSV(langData.strings);

    // Save CSV file
    const csvFileName = `${lang}.csv`;
    fs.writeFileSync(path.join(outputDir, csvFileName), csvContent);
    console.log(`Created language CSV file: ${csvFileName}`);
  });

  // Create a language index file with translation statistics
  const langIndex = {
    metadata: {
      extractedAt: result.metadata.extractedAt,
      languages: Array.from(languages).sort(),
    },
    statistics: {},
  };

  // Calculate statistics for each language
  Array.from(languages).forEach((lang) => {
    if (lang === "en") return; // Skip English as it's the source language

    let totalStrings = 0;
    let translatedStrings = 0;
    let needsReviewStrings = 0;
    let needsTranslationStrings = 0;

    Object.keys(result.strings).forEach((key) => {
      if (result.strings[key].en) {
        totalStrings++;

        if (result.strings[key][lang]) {
          if (result.strings[key][lang].state === "needs_review") {
            needsReviewStrings++;
          } else if (result.strings[key][lang].state === "translated") {
            translatedStrings++;
          } else if (
            result.strings[key][lang].state === "needs_translation" ||
            result.strings[key][lang].value === ""
          ) {
            needsTranslationStrings++;
          }
        } else {
          needsTranslationStrings++;
        }
      }
    });

    langIndex.statistics[lang] = {
      totalStrings,
      translatedStrings,
      needsReviewStrings,
      needsTranslationStrings,
      translationPercentage: totalStrings
        ? Math.round((translatedStrings / totalStrings) * 100)
        : 0,
      needsReviewPercentage: totalStrings
        ? Math.round((needsReviewStrings / totalStrings) * 100)
        : 0,
      needsTranslationPercentage: totalStrings
        ? Math.round((needsTranslationStrings / totalStrings) * 100)
        : 0,
    };
  });

  fs.writeFileSync(
    path.join(outputDir, "languages.json"),
    JSON.stringify(langIndex, null, 2),
  );

  // Print translation summary
  console.log("\n✨ Prebuild: Translation Progress Summary:");
  console.log("============================");
  Object.keys(langIndex.statistics)
    .sort()
    .forEach((lang) => {
      const stats = langIndex.statistics[lang];
      console.log(
        `${lang}: ${stats.translationPercentage}% translated, ${stats.needsReviewPercentage}% needs review, ${stats.needsTranslationPercentage}% needs translation ` +
          `(${stats.translatedStrings}/${stats.totalStrings} translated, ${stats.needsReviewStrings}/${stats.totalStrings} needs review, ${stats.needsTranslationStrings}/${stats.totalStrings} needs translation)`,
      );
    });
  console.log("============================");

  // Count the generated files
  const generatedFiles = fs.readdirSync(outputDir);
  console.log(
    `✨ Prebuild: Generated ${generatedFiles.length} localization files\n`,
  );
} catch (error) {
  console.error(
    `❌ Prebuild: Localization extraction failed: ${error.message}`,
  );
  process.exit(1);
}

export function convertTranslationToCSV(strings) {
  // CSV headers
  let csv = "key,source,target,state,comment\n";

  // Add each string as a row
  Object.entries(strings).forEach(([key, item]) => {
    // Ensure all fields are strings and handle optional fields
    const escapedKey = escapeCSVField(key);
    const escapedSource = escapeCSVField(item.source || "");
    const escapedTarget = escapeCSVField(item.target || "");
    const escapedState = escapeCSVField(item.state || "needs_translation");
    const escapedComment = escapeCSVField(item.comment || "");

    // Add row
    csv += `${escapedKey},${escapedSource},${escapedTarget},${escapedState},${escapedComment}\n`;
  });

  return csv;
}

export function convertSourceToCSV(sourceData) {
  // CSV headers
  let csv = "key,source,target,state,comment\n";

  // Add each string as a row
  Object.entries(sourceData.strings).forEach(([key, item]) => {
    const escapedKey = escapeCSVField(key);
    const escapedSource = escapeCSVField(item.value || "");
    const escapedTarget = escapeCSVField(""); // Empty target for template
    const escapedState = escapeCSVField("needs_translation"); // Default state
    const escapedComment = escapeCSVField(item.comment || "");

    // Add row
    csv += `${escapedKey},${escapedSource},${escapedTarget},${escapedState},${escapedComment}\n`;
  });

  return csv;
}

// Helper function to escape CSV fields properly
function escapeCSVField(field) {
  if (!field) return '""';

  // If the field contains commas, newlines, or quotes, wrap it in quotes and escape internal quotes
  const needsQuotes = /[,\r\n"]/g.test(field);

  if (needsQuotes) {
    // Replace double quotes with two double quotes (CSV escaping)
    const escaped = field.replace(/"/g, '""');
    return `"${escaped}"`;
  }

  return `"${field}"`; // Always wrap in quotes for consistency
}

// ---- Press kit "Download all" zip ----
// Bundles the press assets into public/blankie-press-kit.zip (public/ is
// gitignored build output, so the zip is regenerated each build, never committed).
try {
  const assetsDir = path.join(__dirname, "src", "assets");
  const publicDir = path.join(__dirname, "public");
  const pressFiles = [
    "icon.png",
    "promo.png",
    "blankie-devices.png",
    "mac-mockup.png",
    "ipad-mockup.png",
    "iphone-mockup-1.png",
    "iphone-mockup-2.png",
    "mac-store-1.png",
    "mac-store-2.png",
    "mac-store-3.png",
    "mac-store-4.png",
    "iphone-store-1.png",
    "iphone-store-2.png",
    "iphone-store-3.png",
    "iphone-store-4.png",
    "iphone-store-5.png",
    "ipad-store-1.png",
    "ipad-store-2.png",
    "ipad-store-3.png",
    "ipad-store-4.png",
  ];
  const present = pressFiles.filter((f) =>
    fs.existsSync(path.join(assetsDir, f)),
  );
  if (present.length) {
    fs.mkdirSync(publicDir, { recursive: true });
    const zipPath = path.join(publicDir, "blankie-press-kit.zip");
    fs.rmSync(zipPath, { force: true });
    const args = present.map((f) => `"${path.join(assetsDir, f)}"`).join(" ");
    // -j flattens paths so the archive holds bare filenames, -q is quiet.
    execSync(`zip -j -q "${zipPath}" ${args}`);
    console.log(
      `\n✨ Prebuild: Wrote press kit zip (${present.length} files) -> public/blankie-press-kit.zip`,
    );
  }
} catch (err) {
  console.warn(`⚠️  Prebuild: Skipped press kit zip (${err.message})`);
}
