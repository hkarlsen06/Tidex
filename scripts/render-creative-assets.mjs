#!/usr/bin/env node
// Render the App Store product page header (21:9) and search result (3:2) creative assets from the same
// 3D phones, background and captures as the screenshots. The assets have no text, so each locale only
// swaps the captures. Sizes and formats follow Apple's creative asset specifications: PNG without alpha.
//
// Usage: node scripts/render-creative-assets.mjs [captures-dir] [output-dir] [locale ...]
// Defaults render every locale in ios/ASConnectScreenshots/<version>/raw-dark into .../<version>/creative.
import { readdir, readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { launch, openPage, renderPhones, threeImports } from './lib/phone3d.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const version = (await readFile(path.join(root, 'ios/Version.xcconfig'), 'utf8'))
  .match(/^MARKETING_VERSION = (\S+)/m)[1];
const [capturesArg, outputArg, ...localeArgs] = process.argv.slice(2);
const captures = path.resolve(capturesArg ?? path.join(root, 'ios/ASConnectScreenshots', version, 'raw-dark'));
const output = path.resolve(outputArg ?? path.join(root, 'ios/ASConnectScreenshots', version, 'creative'));
const style = JSON.parse(await readFile(path.join(root, 'scripts/assets/app-store/tidex-3d.json'), 'utf8'));
const locales = localeArgs.length ? localeArgs
  : (await readdir(captures, { withFileTypes: true })).filter(entry => entry.isDirectory()).map(entry => entry.name);

// x, y and height are fractions of the asset. The home screen sits in the middle, where every crop keeps it.
const ASSETS = {
  header: {
    width: 3840, height: 1646,
    phones: [
      { screen: '03-schedule', x: 0.34, y: 0.64, height: 0.94, rotate: [0, 24, 4] },
      { screen: '04-payroll', x: 0.66, y: 0.64, height: 0.94, rotate: [0, -24, -4] },
      { screen: '01-home', x: 0.5, y: 0.6, height: 1.08, rotate: [0, 0, 0] },
    ],
  },
  search: {
    width: 3840, height: 2560,
    phones: [
      { screen: '03-schedule', x: 0.25, y: 0.56, height: 0.8, rotate: [0, 24, 4] },
      { screen: '04-payroll', x: 0.75, y: 0.56, height: 0.8, rotate: [0, -24, -4] },
      { screen: '01-home', x: 0.5, y: 0.52, height: 0.92, rotate: [0, 0, 0] },
    ],
  },
};

const page = ({ width: W, height: H, phones }) => {
  const glows = phones.map(p => `radial-gradient(${p.height * H * 0.55}px ${p.height * H * 0.45}px at `
    + `${p.x * W}px ${p.y * H}px, ${style.glow}, transparent)`);
  return `<!doctype html><meta charset="utf-8">${threeImports}
    <style>
      * { margin: 0; }
      html, body { width: ${W}px; height: ${H}px; overflow: hidden; }
      body { position: relative; background: ${[...glows, style.background].join(', ')}; }
      img { position: absolute; filter: drop-shadow(0 60px 80px #04061a99); }
    </style>`;
};

for (const locale of locales) {
  for (const [name, asset] of Object.entries(ASSETS)) {
    // A fresh browser per asset, as in render-3d-screenshots.mjs: SwiftShader runs low on memory otherwise.
    const browser = await launch(chromium);
    try {
      const files = Object.fromEntries(asset.phones.map(({ screen }) =>
        [screen, style.capture.replaceAll('{locale}', locale).replaceAll('{screen}', screen)]));
      const tab = await openPage(browser, { width: asset.width, height: asset.height, html: page(asset), captures });
      await tab.evaluate(renderPhones, { phones: asset.phones, finish: style.finish, W: asset.width, H: asset.height, captures: files });
      const folder = path.join(output, locale);
      await mkdir(folder, { recursive: true });
      const png = await tab.screenshot({ path: path.join(folder, `${name}.png`) });
      if (png.readUInt32BE(16) !== asset.width || png.readUInt32BE(20) !== asset.height) throw new Error(`Wrong size: ${locale}/${name}.png`);
      if (png[25] !== 2) throw new Error(`${locale}/${name}.png has an alpha channel; App Store Connect rejects it`);
    } finally {
      await browser.close();
    }
  }
  console.log(`Rendered ${Object.keys(ASSETS).join(' and ')} for ${locale} into ${path.join(output, locale)}`);
}
