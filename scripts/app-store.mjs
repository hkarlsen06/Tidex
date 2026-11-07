#!/usr/bin/env node
import { cp, mkdtemp, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { assertEditable, checkPNG, config, releaseVersion, resolveVersion, root, store, versionLocalizations, withAsc } from './lib/app-store-connect.mjs';

const help = `Usage: bun run app-store <metadata|review-metadata|screenshots|validate> [options]
  --apply               Apply changes. The default is a read-only dry run.
  --version VERSION     Defaults to ios/Version.xcconfig.
  --locales en-US,no    Limit the operation to these locales.
  --device TYPE         screenshots only: iphone, ipad, duo, all (default).
  --assets-dir PATH     screenshots only: version screenshot directory.
  --replace             screenshots only: replace each selected device set.
Generate metadata first with bun run --cwd ios generate-metadata.
No command submits for review or releases the app.`;

const devices = {
  iphone: { folder: '3d', prefix: 'iPhone-', count: 5, slot: 'IPHONE_67', sizes: [[1320, 2868]] },
  ipad: { folder: '', prefix: 'iPad-', count: 5, slot: 'IPAD_PRO_3GEN_129', sizes: [[2064, 2752], [2752, 2064]] },
  duo: { folder: '3d-duo', prefix: 'Duo-', count: 10, slot: 'IPHONE_DUO', sizes: [[1398, 2034], [2034, 1398], [2007, 2853], [2853, 2007]] },
};

async function localeFiles(folder) {
  return (await readdir(folder)).filter(name => name.endsWith('.json')).map(name => name.slice(0, -5)).sort();
}

async function stageMetadata(temporary, version, locales, reviewOnly) {
  const source = path.join(store, 'metadata');
  const available = await localeFiles(path.join(source, 'version', version));
  for (const locale of locales ?? available) {
    if (!available.includes(locale)) throw new Error(`No local ${version} metadata for ${locale}`);
    const file = `${locale}.json`;
    const output = path.join(temporary, 'version', version);
    await mkdir(output, { recursive: true });
    const data = JSON.parse(await readFile(path.join(source, 'version', version, file), 'utf8'));
    if (reviewOnly) {
      if (typeof data.promotionalText !== 'string' || !data.promotionalText.trim()) throw new Error(`Missing promotional text for ${locale}`);
      await writeFile(path.join(output, file), JSON.stringify({ promotionalText: data.promotionalText }));
    } else {
      await cp(path.join(source, 'version', version, file), path.join(output, file));
      await mkdir(path.join(temporary, 'app-info'), { recursive: true });
      await cp(path.join(source, 'app-info', file), path.join(temporary, 'app-info', file));
    }
  }
  // Only notes are managed. Existing demo credentials and contact details stay remote.
  const review = JSON.parse(await readFile(path.join(source, 'review-information.json'), 'utf8'));
  if (typeof review.notes !== 'string' || !review.notes.trim() || [...review.notes].length > 4000) throw new Error('Review notes must contain 1 to 4000 characters');
  if (Object.keys(review).some(key => key !== 'notes')) throw new Error('Tidex manages only notes in review-information.json');
  await writeFile(path.join(temporary, 'review-information.json'), JSON.stringify(review));
}

async function screenshotJobs(assets, device, locales, temporary) {
  const jobs = [];
  for (const name of device === 'all' ? Object.keys(devices) : [device]) {
    const spec = devices[name];
    if (!spec) throw new Error(`Unknown screenshot device: ${name}`);
    const directory = path.join(assets, spec.folder);
    const available = (await readdir(directory, { withFileTypes: true }))
      .filter(entry => entry.isDirectory() && (name !== 'ipad' || ['en-US', 'no'].includes(entry.name)))
      .map(entry => entry.name).sort();
    for (const locale of locales ?? available) {
      if (!available.includes(locale)) throw new Error(`No ${name} artwork for ${locale} in ${directory}`);
      const source = path.join(directory, locale);
      const files = (await readdir(source)).filter(file => file.startsWith(spec.prefix) && file.endsWith('.png')).sort();
      if (files.length !== spec.count) throw new Error(`Expected ${spec.count} ${name} screenshots for ${locale}, found ${files.length}`);
      if (name === 'duo' && ['inner', 'outer'].some(display =>
        [1, 2, 3, 4, 5].some(index => !files.includes(`Duo-${display}-0${index}.png`)))) {
        throw new Error(`Duo artwork for ${locale} must contain all five inner and five outer images`);
      }
      const staged = path.join(temporary, name, locale);
      await mkdir(staged, { recursive: true });
      for (const file of files) {
        await cp(path.join(source, file), path.join(staged, file));
        await checkPNG(path.join(staged, file), spec.sizes);
      }
      jobs.push({ device: name, locale, path: staged, slot: spec.slot, count: files.length });
    }
    if (!available.length) throw new Error(`No ${name} screenshot locales in ${directory}`);
  }
  return jobs;
}

async function main() {
  const { values: flags, positionals } = parseArgs({ options: {
    apply: { type: 'boolean' }, 'dry-run': { type: 'boolean' }, help: { type: 'boolean' },
    version: { type: 'string' }, locales: { type: 'string' }, device: { type: 'string' },
    'assets-dir': { type: 'string' }, replace: { type: 'boolean' },
  }, allowPositionals: true });
  if (flags.help || !positionals.length) { console.log(help); return; }
  const [command] = positionals;
  if (positionals.length !== 1 || !['metadata', 'review-metadata', 'screenshots', 'validate'].includes(command)) throw new Error(help);
  if (flags.apply && flags['dry-run']) throw new Error('Choose --apply or --dry-run');
  if (command !== 'screenshots' && (flags.device || flags.replace || flags['assets-dir'])) throw new Error('Device, assets-dir and replace apply only to screenshots');
  if (command === 'validate' && (flags.apply || flags.locales || flags.version)) throw new Error('validate checks all local metadata without applying changes');
  const version = flags.version ?? await releaseVersion();
  if (!/^\d+(?:\.\d+){1,2}$/.test(version)) throw new Error(`Invalid version: ${version}`);
  const locales = flags.locales?.split(',');
  if (locales && (new Set(locales).size !== locales.length || locales.some(locale => !/^[a-z]{2,3}(?:-[A-Za-z0-9]{2,4})*$/.test(locale)))) throw new Error('Pass unique App Store locales separated by commas');
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'tidex-app-store-'));
  try {
    if (command === 'validate') {
      await withAsc(async asc => console.log(JSON.stringify(await asc(['metadata', 'validate', '--dir', path.join(store, 'metadata')]), null, 2)), { authenticate: false });
      return;
    }
    let jobs;
    if (command === 'screenshots') {
      jobs = await screenshotJobs(path.resolve(flags['assets-dir'] ?? path.join(root, 'ios/ASConnectScreenshots', version)), flags.device ?? 'all', locales, temporary);
    } else {
      await stageMetadata(temporary, version, locales, command === 'review-metadata');
    }
    await withAsc(async asc => {
      if (!jobs) await asc(['metadata', 'validate', '--dir', temporary]);
      const remote = await resolveVersion(asc, version);
      if (flags.apply) assertEditable(remote);
      if (!jobs) {
        const args = ['metadata', 'push', '--app', config.appId, '--version', version, '--platform', 'IOS', '--dir', temporary,
          '--include', 'localizations,review-information', '--if-exists', 'update'];
        // Plan the entire operation before the first write, even for --apply.
        const plan = await asc([...args, '--dry-run']);
        console.log(JSON.stringify(plan, null, 2));
        if (command === 'metadata' && remote.attributes.copyright !== config.copyright) {
          console.log(JSON.stringify({ copyright: config.copyright, version, dryRun: !flags.apply }));
        }
        if (flags.apply) {
          console.log(JSON.stringify(await asc([...args, '--confirm']), null, 2));
          if (command === 'metadata' && remote.attributes.copyright !== config.copyright) {
            console.log(JSON.stringify(await asc(['versions', 'update', '--version-id', remote.id, '--copyright', config.copyright])));
          }
        }
        return;
      }
      const localizations = await versionLocalizations(asc, remote.id);
      const uploads = [];
      for (const job of jobs) {
        const localizationID = localizations.get(job.locale);
        if (!localizationID) throw new Error(`Version ${version} has no ${job.locale} localization`);
        const args = ['screenshots', 'upload', '--version-localization', localizationID, '--path', job.path, '--device-type', job.slot,
          ...(flags.replace ? ['--replace'] : ['--skip-existing'])];
        console.log(JSON.stringify({ device: job.device, locale: job.locale, plan: await asc([...args, '--dry-run']) }));
        uploads.push(args);
      }
      if (flags.apply) for (const args of uploads) {
        console.log(JSON.stringify(await asc([...args, ...(flags.replace ? ['--confirm'] : [])])));
      }
    }, { readOnly: !flags.apply });
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
