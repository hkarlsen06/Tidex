#!/usr/bin/env node
// Upload the product page header and search result creative assets from render-creative-assets.mjs to an
// App Store version through the App Asset Library API. fastlane deliver has no support for these assets.
// Each image is reserved, uploaded, committed and placed on the version localization for its locale.
// A localization that already has a placement of that type is skipped, so the script is safe to rerun.
//
// Usage: node scripts/upload-creative-assets.mjs [--dry-run] [--version 3.0.1] [assets-dir]
// Defaults upload ios/ASConnectScreenshots/<version>/creative to the version in ios/Version.xcconfig.
// Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH from ios/fastlane/.env, like the Fastfile.
import { createPrivateKey, sign } from 'node:crypto';
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { readdir, readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { values: flags, positionals } = parseArgs({
  options: { 'dry-run': { type: 'boolean' }, version: { type: 'string' } }, allowPositionals: true,
});
const version = flags.version ?? readFileSync(path.join(root, 'ios/Version.xcconfig'), 'utf8')
  .match(/^MARKETING_VERSION = (\S+)/m)[1];
const assets = path.resolve(positionals[0] ?? path.join(root, 'ios/ASConnectScreenshots', version, 'creative'));
const TYPES = { 'header.png': 'PRODUCT_PAGE_HEADER_ASSET', 'search.png': 'APP_STORE_SEARCH_RESULTS_ASSET' };
const GROUP = 'DEFAULT_PROFILE';

const envFile = path.join(root, 'ios/fastlane/.env');
const env = Object.fromEntries(readFileSync(envFile, 'utf8').split('\n').filter(line => /^\w+=/.test(line))
  .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1).replace(/^["']|["']$/g, '')]));
// When the secrets folder moves, the key is still next to fastlane.env even if ASC_KEY_PATH is stale.
const keyPath = [env.ASC_KEY_PATH, path.join(path.dirname(realpathSync(envFile)), path.basename(env.ASC_KEY_PATH))]
  .find(file => existsSync(file));
if (!keyPath) throw new Error(`App Store Connect API key not found at ${env.ASC_KEY_PATH}`);
const key = createPrivateKey(readFileSync(keyPath));

const token = () => {
  const part = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${part({ alg: 'ES256', kid: env.ASC_KEY_ID, typ: 'JWT' })}.`
    + part({ iss: env.ASC_ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' });
  return `${unsigned}.${sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
};

async function api(method, route, data) {
  const response = await fetch(`https://api.appstoreconnect.apple.com/${route}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: data && JSON.stringify({ data }),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${method} ${route} returned ${response.status}: ${text}`);
  return text ? JSON.parse(text) : null;
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

const [app] = (await api('GET', 'v1/apps?filter[bundleId]=no.tidex.app')).data;
const [appVersion] = (await api('GET', `v1/apps/${app.id}/appStoreVersions?filter[versionString]=${version}&filter[platform]=IOS`)).data;
if (!appVersion) throw new Error(`App Store Connect has no iOS version ${version}`);
const library = (await api('GET', `v1/apps/${app.id}/assetLibrary`)).data.id;
const localizations = Object.fromEntries((await api('GET',
  `v1/appStoreVersions/${appVersion.id}/appStoreVersionLocalizations?limit=200`)).data.map(l => [l.attributes.locale, l.id]));

const jobs = [];
for (const locale of (await readdir(assets, { withFileTypes: true })).filter(e => e.isDirectory()).map(e => e.name)) {
  if (!localizations[locale]) throw new Error(`Version ${version} has no ${locale} localization`);
  for (const [file, placementType] of Object.entries(TYPES)) {
    const placed = await api('GET', `v1/appStoreVersionLocalizations/${localizations[locale]}/placements`
      + `?filter[placementType]=${placementType}&filter[placementGroup]=${GROUP}`);
    if (placed.data.length) console.log(`${locale} ${file}: already placed, skipping`);
    else jobs.push({ locale, file, placementType, localization: localizations[locale] });
  }
}
console.log(`${jobs.length} assets to upload to ${version}${flags['dry-run'] ? ' (dry run, nothing uploaded)' : ''}`);
if (flags['dry-run']) process.exit(0);

async function upload({ locale, file }) {
  const filePath = path.join(assets, locale, file);
  const fileSize = (await stat(filePath)).size;
  const referenceName = `Creative ${version} ${locale} ${file}`;
  // Reuse an image a previous, interrupted run uploaded; drop one whose upload never finished.
  const existing = (await api('GET', `v1/appAssetLibraries/${library}/images`
    + `?filter[referenceName]=${encodeURIComponent(referenceName)}`)).data;
  for (const image of existing.filter(i => ['AWAITING_UPLOAD', 'FAILED'].includes(i.attributes.state))) {
    await api('DELETE', `v1/appAssetLibraryImages/${image.id}`);
  }
  const reusable = existing.find(i => !['AWAITING_UPLOAD', 'FAILED'].includes(i.attributes.state)
    && i.attributes.fileSize === fileSize);
  if (reusable) return reusable.id;

  const image = (await api('POST', 'v1/appAssetLibraryImages', {
    type: 'appAssetLibraryImages',
    attributes: { fileName: `${path.basename(file, '.png')}-${locale}.png`, fileSize, category: 'CREATIVE_ASSETS', referenceName },
    relationships: { assetLibrary: { data: { type: 'appAssetLibraries', id: library } } },
  })).data;
  const bytes = await readFile(filePath);
  await Promise.all(image.attributes.uploadOperations.map(async ({ method, url, offset, length, requestHeaders }) => {
    const response = await fetch(url, {
      method,
      headers: Object.fromEntries(requestHeaders.map(h => [h.name, h.value])),
      body: bytes.subarray(offset, offset + length),
    });
    if (!response.ok) throw new Error(`Uploading ${locale}/${file} returned ${response.status}: ${await response.text()}`);
  }));
  await api('PATCH', `v1/appAssetLibraryImages/${image.id}`,
    { type: 'appAssetLibraryImages', id: image.id, attributes: { uploaded: true } });
  return image.id;
}

async function waitForProcessing(id, label) {
  for (let attempt = 0; attempt < 120; attempt++) {
    const { state, stateDetails } = (await api('GET', `v1/appAssetLibraryImages/${id}`)).data.attributes;
    if (state === 'FAILED') throw new Error(`${label} failed processing: ${JSON.stringify(stateDetails)}`);
    if (state !== 'AWAITING_UPLOAD' && state !== 'UPLOAD_COMPLETE') return;
    await sleep(5000);
  }
  throw new Error(`${label} was still processing after 10 minutes`);
}

const failures = [];
const queue = [...jobs];
await Promise.all(Array.from({ length: 6 }, async () => {
  for (let job; (job = queue.shift());) {
    const label = `${job.locale} ${job.file}`;
    try {
      const image = await upload(job);
      await waitForProcessing(image, label);
      await api('POST', 'v1/appAssetLibraryPlacements', {
        type: 'appAssetLibraryPlacements',
        attributes: { placementType: job.placementType, placementGroup: GROUP },
        relationships: {
          image: { data: { type: 'appAssetLibraryImages', id: image } },
          appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: job.localization } },
        },
      });
      console.log(`${label}: placed`);
    } catch (error) {
      failures.push(label);
      console.error(`${label}: ${error.message}`);
    }
  }
}));
if (failures.length) {
  console.error(`${failures.length} of ${jobs.length} failed. Rerun to retry them: ${failures.join(', ')}`);
  process.exit(1);
}
console.log(`Placed ${jobs.length} creative assets on ${version}`);
