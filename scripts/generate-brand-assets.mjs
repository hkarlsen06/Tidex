#!/usr/bin/env bun
// Regenerate public and in-app branding from the app's approved Icon Composer artwork.
// Run on a Mac with Xcode: bun scripts/generate-brand-assets.mjs
import { readFile, writeFile, mkdir, mkdtemp, rm, cp } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { marketingEn } from '../marketing/lib/i18n/dictionaries/marketing.en.ts';
import { marketingNo } from '../marketing/lib/i18n/dictionaries/marketing.no.ts';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const icon = path.join(root, 'ios/TidexApp/Resources/tidex.icon');
const catalog = path.join(root, 'ios/TidexApp/Resources/Assets.xcassets');
const publicDir = path.join(root, 'marketing/public');
const config = JSON.parse(await readFile(path.join(icon, 'icon.json'), 'utf8'));
const work = await mkdtemp(path.join(tmpdir(), 'tidex-brand-'));
const transparent = { r: 0, g: 0, b: 0, alpha: 0 };
const xml = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

// Let ColorSync convert the Icon Composer Display P3 colours before SVG rasterization.
// The SVG renderer used by sharp does not support CSS color(display-p3 ...).
const encodedColors = [...new Set(JSON.stringify(config).match(/(?:display-p3|srgb|extended-gray):[\d.,]+/g))];
const colors = JSON.parse(execFileSync('swift', ['-e', `
import AppKit
let values = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [String]
var result: [String: String] = [:]
for value in values {
  let parts = value.split(separator: ":")
  let c = parts[1].split(separator: ",").map { CGFloat(Double($0)!) }
  let color: NSColor
  switch parts[0] {
  case "display-p3": color = NSColor(displayP3Red: c[0], green: c[1], blue: c[2], alpha: c[3])
  case "srgb": color = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
  default: color = NSColor(white: c[0], alpha: c[1])
  }
  let rgb = color.usingColorSpace(.sRGB)!
  let bytes = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int((min(1, max(0, $0)) * 255).rounded()) }
  result[value] = String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
}
print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
`], { input: JSON.stringify(encodedColors), encoding: 'utf8' }));

function appearanceValue(specializations, appearance) {
  return (specializations.find(item => item.appearance === appearance)
    ?? specializations.find(item => !item.appearance)).value;
}
const brandBlue = colors[appearanceValue(config['fill-specializations']).solid];

const flatLayerSources = new Map();
const cutoutOutlines = new Map();
async function flatLayerSource(filename) {
  if (flatLayerSources.has(filename)) return flatLayerSources.get(filename);
  const source = await readFile(path.join(icon, 'Assets', filename), 'utf8');
  const flattened = source.replace(/<mask\b[\s\S]*?<\/mask>/g, mask => {
    const id = mask.match(/\bid="([^"]+)"/)?.[1];
    const d = mask.match(/<path\b[^>]*\bd="([^"]+)"/)?.[1];
    const width = mask.match(/\bstroke-width="([\d.]+)"/)?.[1];
    const transform = mask.match(/\btransform="translate\(([-\d.]+) ([-\d.]+)\) rotate\(([-\d.]+)\) scale\(([-\d.]+) ([-\d.]+)\)"/);
    if (!id || !d || !width || !transform || !mask.includes('stroke-linejoin="round"')
      || !mask.includes('maskUnits="userSpaceOnUse"')) {
      throw new Error(`Update the vector cutout conversion for ${filename}.`);
    }
    const tokens = d.match(/[A-Za-z]|[-+]?(?:\d*\.)?\d+(?:[eE][-+]?\d+)?/g);
    if (tokens.some(token => /^[A-Za-z]$/.test(token) && !['M', 'L', 'C', 'Z'].includes(token))) {
      throw new Error(`Unsupported SVG path command in ${filename}.`);
    }
    const [tx, ty, angle, sx, sy] = transform.slice(1).map(Number);
    const radians = angle * Math.PI / 180;
    const contour = { tokens, strokeWidth: Number(width), transform: [
      Math.cos(radians) * sx, Math.sin(radians) * sx,
      -Math.sin(radians) * sy, Math.cos(radians) * sy, tx, ty,
    ] };
    const key = JSON.stringify(contour);
    if (!cutoutOutlines.has(key)) {
      cutoutOutlines.set(key, execFileSync('swift', [path.join(root, 'scripts/assets/brand/outline-cutout.swift')],
        { input: key, encoding: 'utf8' }).trim());
    }
    // The outer canvas and inner contour form a transparent hole using even-odd clipping.
    return `<clipPath id="${id}" clipPathUnits="userSpaceOnUse"><path clip-rule="evenodd" d="M 0 0 H 1024 V 1024 H 0 Z ${cutoutOutlines.get(key)}"/></clipPath>`;
  }).replaceAll('mask="url(', 'clip-path="url(');
  flatLayerSources.set(filename, flattened);
  return flattened;
}

async function markSVG(appearance, monochrome = false) {
  const groups = [];
  // Icon Composer lists the foremost group first; SVG paints it last.
  for (const [groupIndex, group] of [...config.groups].reverse().entries()) {
    const layers = [];
    for (const [layerIndex, layer] of group.layers.entries()) {
      const prefix = `g${groupIndex}l${layerIndex}-`;
      const source = await flatLayerSource(layer['image-name']);
      let inner = source.replace(/^.*?<svg\b[^>]*>/s, '').replace(/<\/svg>\s*$/, '');
      inner = inner.replace(/id="([^"]+)"/g, (_, id) => `id="${prefix}${id}"`)
        .replace(/url\(#([^)]+)\)/g, (_, id) => `url(#${prefix}${id})`);
      let fill = monochrome ? '#000000' : appearance === 'dark' ? '#FFFFFF' : brandBlue;
      let gradient = '';
      if (!monochrome && layer['fill-specializations']) {
        const value = appearanceValue(layer['fill-specializations'], appearance);
        const stops = value['linear-gradient'];
        if (!stops) throw new Error(`Expected a gradient for ${layer['image-name']}`);
        const id = `${prefix}brand`;
        gradient = `<defs><linearGradient id="${id}" x1="0" y1="0.5" x2="1" y2="0.5">`
          + stops.map((color, i) => `<stop offset="${i / (stops.length - 1)}" stop-color="${colors[color]}"/>`).join('')
          + '</linearGradient></defs>';
        fill = `url(#${id})`;
      }
      // Only recolour the drawing, leaving the cutout geometry intact.
      const endOfDefs = inner.lastIndexOf('</defs>') + '</defs>'.length;
      const split = inner.includes('</defs>') ? endOfDefs : 0;
      inner = inner.slice(0, split) + inner.slice(split).replaceAll('fill="white"', `fill="${fill}"`);
      const { scale, 'translation-in-points': [x, y] } = layer.position;
      if (scale !== 1) throw new Error('Update the flat-mark transform for the new Icon Composer layer scale.');
      layers.push(`<g transform="translate(${x} ${y})">${gradient}${inner}</g>`);
    }
    const { scale = 1, 'translation-in-points': [x, y] = [0, 0] } = group.position ?? {};
    groups.push(`<g transform="translate(${512 + x} ${512 + y}) scale(${scale}) translate(-512 -512)">${layers.join('')}</g>`);
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${groups.join('')}</svg>`;
}

async function croppedSVG(svg) {
  const { info } = await sharp(Buffer.from(svg)).trim({ threshold: 0 }).png().toBuffer({ resolveWithObject: true });
  const padding = 2;
  const width = info.width + padding * 2;
  const height = info.height + padding * 2;
  return svg.replace('width="1024" height="1024" viewBox="0 0 1024 1024"',
    `width="${width}" height="${height}" viewBox="${-info.trimOffsetLeft - padding} ${-info.trimOffsetTop - padding} ${width} ${height}"`);
}

async function imageset(name, filename, width, height, sources, inset = 0) {
  const dir = path.join(catalog, `${name}.imageset`);
  const images = [];
  for (const [appearance, svg] of Object.entries(sources)) {
    for (const scale of [1, 2, 3]) {
      const file = `${filename}${appearance === 'dark' ? '-dark' : ''}-${scale}x.png`;
      const drawing = await sharp(Buffer.from(svg)).resize({
        width: Math.round((width - inset * 2) * scale),
        height: Math.round((height - inset * 2) * scale),
        fit: 'contain', background: transparent,
      }).png().toBuffer();
      await sharp({ create: { width: width * scale, height: height * scale, channels: 4, background: transparent } })
        .composite([{ input: drawing, gravity: 'centre' }]).png().toFile(path.join(dir, file));
      images.push({ filename: file, idiom: 'universal', scale: `${scale}x`,
        ...(appearance === 'dark' ? { appearances: [{ appearance: 'luminosity', value: 'dark' }] } : {}) });
    }
  }
  await writeFile(path.join(dir, 'Contents.json'), JSON.stringify({ images, info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
}

try {
  await mkdir(path.join(publicDir, 'brand'), { recursive: true });
  const developer = execFileSync('xcode-select', ['-p'], { encoding: 'utf8' }).trim();
  const ictool = path.resolve(developer, '../Applications/Icon Composer.app/Contents/Executables/ictool');
  const appIcon = path.join(work, 'app-icon.png');
  execFileSync(ictool, [icon, '--export-image', '--output-file', appIcon, '--platform', 'iOS',
    '--rendition', 'Default', '--width', '1024', '--height', '1024', '--scale', '1', '--design-generation', '27']);
  const lockupIcon = await sharp(appIcon).resize(512, 512).png().toBuffer();
  await writeFile(path.join(publicDir, 'brand/tidex-app-icon.png'), lockupIcon);
  const iconHeight = 90;
  const letteringX = iconHeight + 8;
  const marks = {};
  const lockups = {};
  const lettering = await readFile(path.join(root, 'scripts/assets/brand/tidex-lettering.svg'), 'utf8');
  const letteringSize = await sharp(Buffer.from(lettering)).metadata();
  const textWidth = Math.round(letteringSize.width / letteringSize.height * 100);
  let lockupWidth;
  for (const appearance of ['light', 'dark']) {
    marks[appearance] = await croppedSVG(await markSVG(appearance));
    await writeFile(path.join(publicDir, `brand/tidex-mark${appearance === 'dark' ? '-dark' : ''}.svg`), marks[appearance] + '\n');
    const wordmark = lettering.replace('fill="currentColor"', `fill="${appearance === 'dark' ? '#FFFFFF' : brandBlue}"`);
    await writeFile(path.join(publicDir, `brand/tidex-wordmark${appearance === 'dark' ? '-dark' : ''}.svg`), wordmark);
    lockupWidth = letteringX + textWidth;
    const nestedIcon = `<image x="0" y="5" width="${iconHeight}" height="${iconHeight}" href="data:image/png;base64,${lockupIcon.toString('base64')}"/>`;
    const nestedWordmark = wordmark.replace(/width="\d+" height="\d+"/, `x="${letteringX}" y="0" width="${textWidth}" height="100"`);
    lockups[appearance] = `<svg xmlns="http://www.w3.org/2000/svg" width="${lockupWidth}" height="100" viewBox="0 0 ${lockupWidth} 100">${nestedIcon}${nestedWordmark}</svg>`;
    await writeFile(path.join(publicDir, `brand/tidex-lockup${appearance === 'dark' ? '-dark' : ''}.svg`), lockups[appearance] + '\n');
  }
  await writeFile(path.join(publicDir, 'safari-pinned-tab.svg'), await croppedSVG(await markSVG('light', true)) + '\n');

  await imageset('TidexLogo', 'tidex-logo', 140, 94, marks);
  await cp(path.join(catalog, 'TidexLogo.imageset'),
    path.join(root, 'ios/TidexShiftWidget/Assets.xcassets/TidexLogo.imageset'), { recursive: true });
  await imageset('TidexWordmark', 'tidex-wordmark', Math.round(lockupWidth * 0.32), 32, lockups);
  await imageset('Splash', 'splash', 300, 300, marks, 40);
  await imageset('TidexLaunchLogo', 'tidex-launch-logo', 150, 150, marks, 20);
  await sharp(Buffer.from(lockups.light)).resize({ width: 910, height: 350, fit: 'contain', background: transparent })
    .png().toFile(path.join(publicDir, 'icons/image.png'));
  await sharp(Buffer.from(lockups.light)).resize({ width: 910, height: 350, fit: 'contain', background: transparent })
    .webp({ lossless: true }).toFile(path.join(publicDir, 'icons/tidex-wordmark.webp'));

  for (const size of [16, 32, 48, 192]) {
    await sharp(appIcon).resize(size, size).flatten({ background: brandBlue }).png()
      .toFile(path.join(publicDir, `favicon-${size}x${size}.png`));
  }
  for (const [file, size] of [['apple-touch-icon.png', 180], ['android-chrome-512x512.png', 512]]) {
    await sharp(appIcon).resize(size, size).flatten({ background: brandBlue }).png().toFile(path.join(publicDir, file));
  }
  await cp(path.join(publicDir, 'apple-touch-icon.png'), path.join(catalog, 'MarketingAppIcon.imageset/apple-touch-icon.png'));

  const sizes = [16, 32, 48, 256];
  const icoImages = await Promise.all(sizes.map(size => sharp(appIcon).resize(size, size).png().toBuffer()));
  const header = Buffer.alloc(6 + sizes.length * 16);
  header.writeUInt16LE(1, 2); header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  for (const [i, size] of sizes.entries()) {
    const entry = 6 + i * 16;
    header[entry] = size % 256; header[entry + 1] = size % 256;
    header.writeUInt16LE(1, entry + 4); header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(icoImages[i].length, entry + 8); header.writeUInt32LE(offset, entry + 12);
    offset += icoImages[i].length;
  }
  await writeFile(path.join(publicDir, 'favicon.ico'), Buffer.concat([header, ...icoImages]));

  const favicon = (await markSVG('dark')).replace('viewBox="0 0 1024 1024">',
    `viewBox="0 0 1024 1024"><rect width="1024" height="1024" rx="224" fill="${brandBlue}"/>`);
  await writeFile(path.join(publicDir, 'favicon.svg'), favicon + '\n');

  const font = path.join(root, 'scripts/assets/app-store/Poppins-SemiBold.ttf');
  for (const [locale, copy] of [['en', marketingEn], ['no', marketingNo]]) {
    const title = await sharp({ text: { text: `<span foreground="#FFFFFF">${xml(copy.hero.title)}</span>`,
      font: 'Poppins SemiBold 66', fontfile: font, width: 650, rgba: true, spacing: 8 } }).png().toBuffer();
    const logo = await sharp(Buffer.from(lockups.dark)).resize({ width: 240 }).png().toBuffer();
    const iconImage = await sharp(appIcon).resize(340, 340).png().toBuffer();
    const background = Buffer.from('<svg width="1200" height="630" xmlns="http://www.w3.org/2000/svg"><defs><radialGradient id="glow"><stop stop-color="#19325E"/><stop offset="1" stop-color="#080E19"/></radialGradient></defs><rect width="1200" height="630" fill="#080E19"/><ellipse cx="1020" cy="170" rx="760" ry="620" fill="url(#glow)"/></svg>');
    const domain = await sharp({ text: { text: '<span foreground="#9AAEC7">tidex.no</span>',
      font: 'Poppins SemiBold 24', fontfile: font, rgba: true } }).png().toBuffer();
    await sharp(background).composite([{ input: logo, left: 66, top: 62 }, { input: title, left: 66, top: 207 },
      { input: iconImage, left: 816, top: 165 }, { input: domain, left: 68, top: 545 }])
      .png().toFile(path.join(publicDir, `og/landing-${locale}.png`));
  }
  await cp(path.join(publicDir, 'og/landing-no.png'), path.join(publicDir, 'og/landing.png'));
  await cp(icon, path.join(root, 'ios/TidexWatchApp/tidex.icon'), { recursive: true });
  console.log('Generated iOS/watchOS branding, adaptive marks, website icons, and localized social previews.');
} finally {
  await rm(work, { recursive: true, force: true });
}
