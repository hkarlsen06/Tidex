#!/usr/bin/env node
// Render one ordered Duo story, with closed and open devices on consistent canvases.
// Usage: node scripts/render-duo-screenshots.mjs [captures-dir] [output-dir] [locale ...]
import { readFile, readdir, mkdir, mkdtemp, cp, rename, rm, stat } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const version = (await readFile(path.join(root, 'ios/Version.xcconfig'), 'utf8'))
  .match(/^MARKETING_VERSION = (\S+)/m)[1];
const [capturesArg, outputArg, ...localeArgs] = process.argv.slice(2);
const captures = path.resolve(capturesArg ?? path.join(root, 'ios/ASConnectScreenshots', version, 'duo'));
const output = path.resolve(outputArg ?? path.join(root, 'ios/ASConnectScreenshots', version, '3d-duo'));
const available = (await readdir(captures, { withFileTypes: true })).filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
const locales = localeArgs.length ? [...new Set(localeArgs)] : available;
if (!locales.length) throw new Error(`No Duo capture locales in ${captures}`);
if (locales.some(locale => !available.includes(locale))) throw new Error('Select locale directories present in the Duo captures');

await mkdir(path.dirname(output), { recursive: true });
const staging = await mkdtemp(path.join(path.dirname(output), '.duo-artwork-'));
const rendered = path.join(staging, 'rendered');
const previous = path.join(staging, 'previous');
let keepStaging = false;
try {
  const existing = await stat(output).catch(error => {
    if (error.code !== 'ENOENT') throw error;
    return null;
  });
  if (existing) await cp(output, rendered, { recursive: true });
  else await mkdir(rendered);
  for (const locale of locales) {
    await rm(path.join(rendered, locale), { recursive: true, force: true });
    for (const display of ['inner', 'outer']) {
      await rm(path.join(rendered, `${locale}-Duo-${display}-preview.png`), { force: true });
    }
  }
  const result = spawnSync(process.execPath, [path.join(root, 'scripts/render-3d-screenshots.mjs'),
    path.join(root, 'scripts/assets/app-store/tidex-duo-3d.json'), captures, rendered, ...locales],
  { stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error('Duo story artwork failed; previous artwork was preserved');
  if (existing) await rename(output, previous);
  try {
    await rename(rendered, output);
  } catch (error) {
    if (existing) {
      try { await rename(previous, output); }
      catch (rollbackError) {
        keepStaging = true;
        throw new AggregateError([error, rollbackError], `Previous artwork is preserved at ${previous}`);
      }
    }
    throw error;
  }
  console.log(`Finished Duo artwork for ${locales.join(', ')} in ${output}`);
} finally {
  if (!keepStaging) await rm(staging, { recursive: true, force: true });
}
