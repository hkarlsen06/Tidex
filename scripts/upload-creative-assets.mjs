#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { cp, mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { assertEditable, checkPNG, config, releaseVersion, resolveVersion, root, versionLocalizations, withAsc } from './lib/app-store-connect.mjs';

const types = {
  'header.png': { placement: 'PRODUCT_PAGE_HEADER_ASSET', size: [3840, 1646] },
  'search.png': { placement: 'APP_STORE_SEARCH_RESULTS_ASSET', size: [3840, 2560] },
};

async function main() {
  const { values: flags, positionals } = parseArgs({ options: {
    apply: { type: 'boolean' }, 'dry-run': { type: 'boolean' }, version: { type: 'string' },
    locales: { type: 'string' }, help: { type: 'boolean' },
  }, allowPositionals: true });
  if (flags.help) {
    console.log('Usage: bun run screenshots:creative:upload [--version VERSION] [--locales en-US,no] [--apply] [assets-dir]\nDefaults to a read-only dry run. Existing header and search placements are preserved.');
    return;
  }
  if (positionals.length > 1 || (flags.apply && flags['dry-run'])) throw new Error('Pass one assets directory and choose --apply or --dry-run');
  const version = flags.version ?? await releaseVersion();
  if (!/^\d+(?:\.\d+){1,2}$/.test(version)) throw new Error(`Invalid version: ${version}`);
  const assets = path.resolve(positionals[0] ?? path.join(root, 'ios/ASConnectScreenshots', version, 'creative'));
  const available = (await readdir(assets, { withFileTypes: true })).filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
  const locales = flags.locales?.split(',') ?? available;
  if (!locales.length || new Set(locales).size !== locales.length || locales.some(locale => !available.includes(locale))) throw new Error('Select unique locales with local creative artwork');
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'tidex-creative-'));
  try {
    const files = [];
    for (const locale of locales) for (const [name, type] of Object.entries(types)) {
      const source = path.join(assets, locale, name);
      const file = path.join(temporary, `${locale}-${name}`);
      await cp(source, file);
      await checkPNG(file, [type.size]);
      const digest = createHash('sha256').update(await readFile(file)).digest('hex');
      files.push({ locale, name, type: type.placement, file, reference: `Tidex ${version} ${locale} ${name} ${digest}` });
    }
    await withAsc(async asc => {
      const remote = await resolveVersion(asc, version);
      if (flags.apply) assertEditable(remote);
      const localizations = await versionLocalizations(asc, remote.id);
      const library = (await asc(['asset-library', 'view', '--app', config.appId])).data.id;
      const jobs = [];
      // Resolve every locale, placement and reusable image before uploading anything.
      for (const locale of locales) {
        const localization = localizations.get(locale);
        if (!localization) throw new Error(`Version ${version} has no ${locale} localization`);
        const placed = await asc(['localizations', 'placements', 'list', '--localization-id', localization,
          '--placement-group', 'DEFAULT_PROFILE', '--placement-type', Object.values(types).map(type => type.placement).join(','), '--paginate']);
        for (const item of files.filter(file => file.locale === locale)) {
          if (placed.data.some(placement => placement.attributes.placementType === item.type)) {
            console.log(`${locale} ${item.name}: already placed, skipping`);
            continue;
          }
          const existing = await asc(['asset-library', 'images', 'list', '--library-id', library, '--reference-name', item.reference, '--paginate']);
          const reusable = existing.data.find(image => image.attributes.imageAsset?.width > 0
            && !['AWAITING_UPLOAD', 'UPLOAD_COMPLETE', 'FAILED'].includes(image.attributes.state));
          if (existing.data.length && !reusable) throw new Error(`${locale} ${item.name}: previous upload is not ready. Inspect image ${existing.data[0].id} with asc before retrying.`);
          jobs.push({ ...item, localization, image: reusable?.id });
        }
      }
      console.log(JSON.stringify({ version, dryRun: !flags.apply, jobs: jobs.map(({ locale, name, image }) => ({ locale, file: name, reuseImage: image ?? null })) }));
      if (!flags.apply) return;
      for (const job of jobs) {
        let image = job.image;
        if (!image) {
          const receipt = await asc(['asset-library', 'images', 'upload', '--library-id', library, '--file', job.file,
            '--category', 'CREATIVE_ASSETS', '--reference-name', job.reference]);
          console.log(JSON.stringify(receipt));
          if (!receipt.ready || !receipt.imageId) throw new Error(`${job.locale} ${job.name}: image did not finish processing`);
          image = receipt.imageId;
        }
        console.log(JSON.stringify(await asc(['localizations', 'placements', 'create', '--localization-id', job.localization,
          '--image-id', image, '--placement-type', job.type, '--placement-group', 'DEFAULT_PROFILE'])));
      }
    }, { readOnly: !flags.apply });
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
