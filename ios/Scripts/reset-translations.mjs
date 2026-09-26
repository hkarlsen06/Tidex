#!/usr/bin/env bun
/**
 * Removes all translations except English (en) and Norwegian (nb)
 * so they can be regenerated with better context.
 */
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const KEEP_LANGUAGES = ["en", "nb"];

const xcstringsFiles = [
  path.join(__dirname, "../Resources/Localization/App/Localizable.xcstrings"),
  path.join(__dirname, "../Resources/Localization/ShareExtension/Localizable.xcstrings"),
  path.join(__dirname, "../Resources/Localization/Widget/Localizable.xcstrings"),
];

async function resetTranslations(filePath) {
  console.log(`\nProcessing: ${filePath}`);

  const content = await fs.readFile(filePath, "utf-8");
  const data = JSON.parse(content);

  let removedCount = 0;
  let keptCount = 0;

  for (const [key, entry] of Object.entries(data.strings)) {
    if (!entry.localizations) continue;

    const langsToRemove = Object.keys(entry.localizations).filter(
      (lang) => !KEEP_LANGUAGES.includes(lang)
    );

    for (const lang of langsToRemove) {
      delete entry.localizations[lang];
      removedCount++;
    }

    keptCount += Object.keys(entry.localizations).length;
  }

  await fs.writeFile(filePath, JSON.stringify(data, null, 2) + "\n");

  console.log(`  Removed: ${removedCount} translations`);
  console.log(`  Kept: ${keptCount} translations (en, nb)`);
}

console.log("Reset Translations");
console.log("==================");
console.log(`Keeping only: ${KEEP_LANGUAGES.join(", ")}`);

for (const file of xcstringsFiles) {
  try {
    await resetTranslations(file);
  } catch (error) {
    console.error(`Error processing ${file}: ${error.message}`);
  }
}

console.log("\n✓ Done! Run translate-xcstrings.mjs to regenerate translations.");
