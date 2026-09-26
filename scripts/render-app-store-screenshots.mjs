#!/usr/bin/env node
// Compose the existing Tidex marketing layout around unmodified simulator captures.
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const version = (await readFile(path.join(root, 'ios/Version.xcconfig'), 'utf8'))
  .match(/^MARKETING_VERSION = (\S+)/m)[1];
const output = path.resolve(process.argv[2] ?? path.join(root, 'ios/ASConnectScreenshots', version));
const raw = path.join(output, 'raw-dark');
const font = (await readFile(path.join(root, 'scripts/assets/app-store/Poppins-SemiBold.ttf'))).toString('base64');
const captions = {
  'en-US': [
    ['01-home', 'Know what<br>payday brings'],
    ['05-add', 'Calculate pay<br>for every shift'],
    ['03-schedule', 'Get the full overview'],
    ['04-payroll', 'See every<br>supplement'],
    ['06-wagey', 'Ask anything<br>about your shifts'],
    ['02-statistics', 'Follow your<br>earnings over time'],
  ],
  no: [
    ['01-home', 'Se hva du får<br>på lønningsdagen'],
    ['05-add', 'Beregn lønn<br>for hver vakt'],
    ['03-schedule', 'Få full oversikt'],
    ['04-payroll', 'Se alle<br>lønnstillegg'],
    ['06-wagey', 'Spør om alt<br>rundt vaktene dine'],
    ['02-statistics', 'Følg inntekten<br>over tid'],
  ],
};
const browser = await chromium.launch({ headless: true });
try {
  for (const [locale, screens] of Object.entries(captions)) {
    const folder = path.join(output, locale);
    await mkdir(folder, { recursive: true });
    for (const [family, width, height] of [['iPhone', 1320, 2868], ['iPad', 2064, 2752]]) {
      const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
      const previews = [];
      for (const [index, [screen, caption]] of screens.entries()) {
        const bytes = await readFile(path.join(raw, locale, `${family}-${screen}.png`));
        if (bytes.readUInt32BE(16) !== width || bytes.readUInt32BE(20) !== height) {
          throw new Error(`Wrong ${family} capture dimensions: ${screen}`);
        }
        const bottom = index % 2 === 1;
        const html = `<!doctype html><html lang="${locale}"><meta charset="utf-8">
          <style>
            * { box-sizing: border-box; }
            html, body { margin: 0; width: ${width}px; height: ${height}px; overflow: hidden; }
            @font-face { font-family: Poppins; font-weight: 600; src: url(data:font/ttf;base64,${font}); }
            body { background: linear-gradient(204deg, #1f1d58, #658fe2); }
            h1 { position: absolute; margin: 0; left: 5%; width: 90%;
              ${bottom ? 'bottom' : 'top'}: ${family === 'iPhone' ? '4.7%' : '3.1%'};
              height: ${family === 'iPhone' ? '8.4%' : '7.2%'};
              display: flex; align-items: center; justify-content: center; text-align: center;
              color: white; font: 600 ${family === 'iPhone' ? '103px' : '112px'}/1.08 Poppins, sans-serif;
            }
            img { position: absolute; display: block; object-fit: contain;
              width: ${family === 'iPhone' ? '80%' : '82%'}; height: auto;
              left: ${family === 'iPhone' ? '10%' : '9%'};
              ${bottom ? 'top' : 'bottom'}: 4%;
              border-radius: ${family === 'iPhone' ? '58px' : '38px'};
              box-shadow: 0 17px 32px #080c2b65, 0 3px 8px #080c2b55;
            }
            .pay-arrow { position: absolute; width: 12%; height: 5.5%; left: 67%; top: 12.5%; }
          </style><h1><span>${caption}</span></h1>
          <img alt="Tidex ${screen}" src="data:image/png;base64,${bytes.toString('base64')}">
          ${screen === '05-add' && family === 'iPhone' ? `<svg class="pay-arrow" viewBox="0 0 150 150">
            <path d="M15 135 L121 29" stroke="#d72308" stroke-width="17" fill="none"/>
            <path d="M93 22 L145 6 L129 58 Z" fill="#d72308"/>
          </svg>` : ''}`;
        await page.setContent(html);
        await page.evaluate(async () => {
          await document.fonts.ready;
          await Promise.all([...document.images].map(image => image.decode()));
          const capture = document.images[0];
          const heading = document.querySelector('h1 span').getBoundingClientRect();
          const screen = capture.getBoundingClientRect();
          if (heading.top < 0 || heading.bottom > innerHeight || heading.left < 0 || heading.right > innerWidth
              || !(heading.bottom <= screen.top || heading.top >= screen.bottom)) {
            throw new Error('Marketing caption is clipped or overlaps the app capture');
          }
          const canvas = document.createElement('canvas');
          canvas.width = capture.naturalWidth;
          canvas.height = capture.naturalHeight;
          const context = canvas.getContext('2d');
          context.drawImage(capture, 0, 0);
          const [r, g, b] = context.getImageData(1, Math.floor(canvas.height / 2), 1, 1).data;
          if (Math.max(r, g, b) > 120) throw new Error('Capture is not in dark mode');
        });
        const name = `${family}-${String(index + 1).padStart(2, '0')}-${screen.slice(3)}.png`;
        await page.screenshot({ path: path.join(folder, name), type: 'png', omitBackground: false });
        previews.push({ name, source: (await readFile(path.join(folder, name))).toString('base64') });
      }
      await page.close();
      const preview = await browser.newPage({ viewport: { width: 1740, height: family === 'iPhone' ? 618 : 398 } });
      await preview.setContent(`<style>body{margin:0;padding:24px;display:flex;gap:24px;background:white}
        img{width:262px;height:auto;border-radius:30px;align-self:flex-start}</style>`
        + previews.map(p => `<img alt="${p.name}" src="data:image/png;base64,${p.source}">`).join(''));
      await preview.evaluate(() => Promise.all([...document.images].map(image => image.decode())));
      await preview.screenshot({ path: path.join(output, `${locale}-${family}-preview.png`) });
      await preview.close();
      console.log(`Rendered ${screens.length} ${locale} ${family} marketing screenshots`);
    }
  }
} finally {
  await browser.close();
}
