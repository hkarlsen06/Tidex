#!/usr/bin/env node
// Render App Store screenshots with 3D iPhone 17 Pro Max models around unmodified simulator captures.
// Every panel is cut from one wide canvas, so a phone placed on a panel boundary continues into the
// next screenshot. The phone model is in lib/phone3d.mjs.
//
// Usage: node scripts/render-3d-screenshots.mjs [config.json] [captures-dir] [output-dir]
// Defaults render Tidex from ios/ASConnectScreenshots/<version>/raw-dark into .../<version>/3d.
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { launch, openPage, renderPhones, threeImports } from './lib/phone3d.mjs';

const W = 1320, H = 2868; // 6.9-inch App Store size, also the capture size.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const version = (await readFile(path.join(root, 'ios/Version.xcconfig'), 'utf8'))
  .match(/^MARKETING_VERSION = (\S+)/m)[1];
const configPath = path.resolve(process.argv[2] ?? path.join(root, 'scripts/assets/app-store/tidex-3d.json'));
const captures = path.resolve(process.argv[3] ?? path.join(root, 'ios/ASConnectScreenshots', version, 'raw-dark'));
const output = path.resolve(process.argv[4] ?? path.join(root, 'ios/ASConnectScreenshots', version, '3d'));
const config = JSON.parse(await readFile(configPath, 'utf8'));

// The App Store lists screenshots right to left in RTL languages, so those strips are mirrored:
// panel i sits in slot count - 1 - i and the phones swap sides and tilt the other way.
const layout = locale => {
  const count = config.panels[locale].length;
  const info = new Intl.Locale(locale);
  const rtl = (info.getTextInfo?.() ?? info.textInfo).direction === 'rtl';
  const slot = i => rtl ? count - 1 - i : i;
  const phones = rtl
    ? config.phones.map(p => ({ ...p, x: count - p.x, rotate: [p.rotate[0], -p.rotate[1], -p.rotate[2]] }))
    : config.phones;
  // Poppins covers Latin only; other scripts use the system font for the page language.
  const latin = config.panels[locale].flat().every(text => /^[\u0000-\u024F\u2000-\u206F]*$/.test(text));
  return { count, rtl, slot, phones, font: latin ? 'Display' : 'system-ui' };
};

const page = (locale, { count, rtl, slot, phones, font }) => {
  // A soft light behind every phone, so the ones on a boundary light both panels.
  const glows = phones.map(p => `radial-gradient(${p.height * H * 0.55}px ${p.height * H * 0.45}px at `
    + `${p.x * W}px ${p.y * H}px, ${config.glow}, transparent)`);
  return `<!doctype html><html lang="${locale}" dir="${rtl ? 'rtl' : 'ltr'}"><meta charset="utf-8">${threeImports}
    <style>
      * { box-sizing: border-box; margin: 0; }
      @font-face { font-family: Display; font-weight: 600; src: url(/font${path.extname(config.font)}); }
      html, body { width: ${W * count}px; height: ${H}px; overflow: hidden; }
      body { position: relative; background: ${[...glows, config.background].join(', ')}; color: white; }
      section { position: absolute; top: ${H * 0.052}px; width: ${W - 220}px; font: 600 104px ${font}, sans-serif; }
      h1 { font-size: 1em; line-height: 1.08; letter-spacing: -0.015em; text-wrap: balance; }
      h1 em { font-style: normal; color: ${config.accent}; }
      h1, p { word-break: auto-phrase; } /* Japanese breaks between phrases, not inside words. */
      :is(:lang(ko), :lang(zh)) :is(h1, p) { word-break: keep-all; } /* Break at spaces and punctuation. */
      p { margin-top: 0.38em; font-size: 0.48em; line-height: 1.32; opacity: 0.72; text-wrap: balance; }
      img { position: absolute; filter: drop-shadow(0 60px 80px #04061a99); }
    </style>
    ${config.panels[locale].map(([headline, body], i) =>
      `<section data-slot="${slot(i)}" style="left: ${slot(i) * W + 110}px"><h1>${headline}</h1><p>${body}</p></section>`)
      .join('')}`;
};

for (const locale of Object.keys(config.panels)) {
  // A fresh browser per locale: SwiftShader runs out of memory on the second wide strip otherwise.
  const browser = await launch(chromium);
  try {
    const count = config.panels[locale].length;
    const files = {};
    for (const { screen } of config.phones) {
      files[screen] = config.capture.replaceAll('{locale}', locale).replaceAll('{screen}', screen);
      const bytes = await readFile(path.join(captures, files[screen]));
      if (bytes.readUInt32BE(16) !== W || bytes.readUInt32BE(20) !== H) throw new Error(`Wrong capture size: ${files[screen]}`);
    }
    const strip = layout(locale);
    const tab = await openPage(browser, {
      width: W * count, height: H, html: page(locale, strip), captures,
      font: path.resolve(path.dirname(configPath), config.font),
    });
    await tab.evaluate(renderPhones, { phones: strip.phones, finish: config.finish, W, H, captures: files });

    const folder = path.join(output, locale);
    await mkdir(folder, { recursive: true });
    const shots = [];
    for (let i = 0; i < count; i++) {
      const name = `iPhone-${String(i + 1).padStart(2, '0')}.png`;
      shots.push(await tab.screenshot({ path: path.join(folder, name), clip: { x: strip.slot(i) * W, y: 0, width: W, height: H } }));
    }
    await tab.close();

    const preview = await browser.newPage({ viewport: { width: 24 + count * 344, height: 796 } });
    await preview.setContent(`<style>body{margin:0;padding:24px;display:flex;gap:24px;background:white;
      flex-direction:${strip.rtl ? 'row-reverse' : 'row'}}
      img{width:320px;border-radius:30px}</style>`
      + shots.map(png => `<img src="data:image/png;base64,${png.toString('base64')}">`).join(''));
    await preview.evaluate(() => Promise.all([...document.images].map(image => image.decode())));
    await preview.screenshot({ path: path.join(output, `${locale}-iPhone-preview.png`) });
    await preview.close();
    console.log(`Rendered ${count} ${locale} 3D screenshots into ${folder}`);
  } finally {
    await browser.close();
  }
}
