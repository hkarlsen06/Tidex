#!/usr/bin/env node
// Render App Store screenshots with 3D iPhone 17 Pro Max models around unmodified simulator captures.
// Every panel is cut from one wide canvas, so a phone placed on a panel boundary continues into the
// next screenshot. WebGL runs on SwiftShader, so reruns match to within a few levels per channel.
//
// Usage: node scripts/render-3d-screenshots.mjs [config.json] [captures-dir] [output-dir]
// Defaults render Tidex from ios/ASConnectScreenshots/<version>/raw-dark into .../<version>/3d.
import { readFile, mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const W = 1320, H = 2868; // 6.9-inch App Store size, also the capture size.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const version = (await readFile(path.join(root, 'ios/Version.xcconfig'), 'utf8'))
  .match(/^MARKETING_VERSION = (\S+)/m)[1];
const configPath = path.resolve(process.argv[2] ?? path.join(root, 'scripts/assets/app-store/tidex-3d.json'));
const captures = path.resolve(process.argv[3] ?? path.join(root, 'ios/ASConnectScreenshots', version, 'raw-dark'));
const output = path.resolve(process.argv[4] ?? path.join(root, 'ios/ASConnectScreenshots', version, '3d'));
const config = JSON.parse(await readFile(configPath, 'utf8'));
const threeDir = path.resolve(createRequire(import.meta.url).resolve('three'), '../..');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf' };

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
  return `<!doctype html><html lang="${locale}" dir="${rtl ? 'rtl' : 'ltr'}"><meta charset="utf-8">
    <script type="importmap">{"imports":{"three":"/three/build/three.module.js","three/addons/":"/three/examples/jsm/"}}</script>
    <script type="module">
      import * as THREE from 'three';
      import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
      import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
      import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
      window.lib = { THREE, RoomEnvironment, RoundedBoxGeometry, mergeVertices };
    </script>
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

// Runs in the page. Builds one phone model, renders each capture on it into its own transparent
// canvas and places that canvas on the strip. Returns nothing; throws if the layout is broken.
async function renderPhones({ phones, finish, W, H, captures }) {
  const { THREE, RoomEnvironment, RoundedBoxGeometry, mergeVertices } = window.lib;
  // iPhone 17 Pro Max in millimetres. B is the radius of the rounded frame edge.
  const width = 78, height = 163.4, depth = 8.75, radius = 13.5, B = 1.4;
  const glassW = width - 2 * B, glassH = height - 2 * B;
  const pxPerMm = 460 / 25.4; // 460 ppi, so a 1320 x 2868 capture fills the display exactly.
  const outline = (w, h, r) => {
    const s = new THREE.Shape(), x = w / 2, y = h / 2;
    s.moveTo(-x + r, -y);
    s.lineTo(x - r, -y); s.quadraticCurveTo(x, -y, x, -y + r);
    s.lineTo(x, y - r); s.quadraticCurveTo(x, y, x - r, y);
    s.lineTo(-x + r, y); s.quadraticCurveTo(-x, y, -x, y - r);
    s.lineTo(-x, -y + r); s.quadraticCurveTo(-x, -y, -x + r, -y);
    return s;
  };

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
  const gl = renderer.getContext();
  const gpu = gl.getParameter(gl.getExtension('WEBGL_debug_renderer_info')?.UNMASKED_RENDERER_WEBGL ?? gl.RENDERER);
  if (!/swiftshader/i.test(gpu)) throw new Error(`WebGL is not on SwiftShader (${gpu}); output would vary by GPU`);
  renderer.setPixelRatio(1);
  renderer.setClearColor(0, 0);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;

  const scene = new THREE.Scene();
  scene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
  const key = new THREE.DirectionalLight('#ffffff', 2.5);
  key.position.set(-1.5, 2, 3);
  scene.add(key);

  const phone = new THREE.Group();
  scene.add(phone);
  const metal = new THREE.MeshPhysicalMaterial({ color: finish, metalness: 1, roughness: 0.32, clearcoat: 0.4 });
  let frame = new THREE.ExtrudeGeometry(outline(glassW, glassH, radius - B), {
    depth: depth - 2 * B, bevelEnabled: true, bevelSize: B, bevelThickness: B, bevelSegments: 12, curveSegments: 32,
  });
  // Extrusions come out flat shaded. Weld the vertices so the rounded edge shades smoothly.
  frame.deleteAttribute('uv');
  frame.deleteAttribute('normal');
  frame = mergeVertices(frame);
  frame.computeVertexNormals();
  frame.translate(0, 0, -(depth - 2 * B) / 2);
  phone.add(new THREE.Mesh(frame, metal));

  // Side buttons: [side, centre from the top, length, material].
  const sapphire = new THREE.MeshPhysicalMaterial({ color: '#111318', metalness: 0.2, roughness: 0.1, clearcoat: 1 });
  for (const [side, fromTop, length, material] of [
    [-1, 31, 7, metal], [-1, 46, 13, metal], [-1, 62, 13, metal], [1, 50, 19, metal], [1, 112, 17, sapphire],
  ]) {
    const button = new THREE.Mesh(new RoundedBoxGeometry(1.4, length, 2.6, 4, 0.6), material);
    button.position.set(side * (width / 2 - 0.1 - (material === sapphire ? 0.4 : 0)), height / 2 - fromTop, 0);
    phone.add(button);
  }

  const glassGeometry = new THREE.ShapeGeometry(outline(glassW, glassH, radius - B), 32);
  const uv = glassGeometry.attributes.uv; // Shape coordinates in millimetres; map them onto the texture.
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) / glassW + 0.5, uv.getY(i) / glassH + 0.5);
  const glassMaterial = new THREE.MeshBasicMaterial({ toneMapped: false });
  const glass = new THREE.Mesh(glassGeometry, glassMaterial);
  glass.position.z = depth / 2 + 0.01;
  phone.add(glass);

  const fov = 16;
  const vertex = new THREE.Vector3();
  const layer = document.createElement('div');
  document.body.append(layer);
  const bounds = [];
  for (const spec of phones) {
    const capture = new Image();
    capture.src = `/capture/${captures[spec.screen]}`;
    await capture.decode();
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(glassW * pxPerMm);
    canvas.height = Math.round(glassH * pxPerMm);
    const c = canvas.getContext('2d');
    const x0 = (canvas.width - W) / 2, y0 = (canvas.height - H) / 2;
    c.fillStyle = '#030304';
    c.fillRect(0, 0, canvas.width, canvas.height);
    c.save();
    c.beginPath();
    c.roundRect(x0, y0, W, H, 186);
    c.clip();
    c.drawImage(capture, x0, y0);
    c.restore();
    c.fillStyle = '#000';
    c.beginPath();
    c.roundRect(canvas.width / 2 - 189, y0 + 33, 378, 111, 55.5); // Dynamic Island
    c.fill();
    const glare = c.createLinearGradient(0, 0, canvas.width, canvas.height * 0.6);
    glare.addColorStop(0, '#ffffff14');
    glare.addColorStop(0.46, '#ffffff05');
    glare.addColorStop(0.46, '#ffffff00');
    c.fillStyle = glare;
    c.fillRect(0, 0, canvas.width, canvas.height);
    glassMaterial.map?.dispose();
    glassMaterial.map = new THREE.CanvasTexture(canvas);
    glassMaterial.map.colorSpace = THREE.SRGBColorSpace;
    glassMaterial.map.anisotropy = renderer.capabilities.getMaxAnisotropy();
    glassMaterial.needsUpdate = true;

    // Frame the camera so the phone is spec.height of the panel tall, with room for any rotation.
    const phonePx = spec.height * H, size = Math.ceil(phonePx * 1.35);
    const camera = new THREE.PerspectiveCamera(fov, 1, 10, 10000);
    camera.position.z = (height * size / phonePx) / 2 / Math.tan(THREE.MathUtils.degToRad(fov / 2));
    phone.rotation.set(...spec.rotate.map(THREE.MathUtils.degToRad), 'ZYX');
    phone.updateMatrixWorld();
    renderer.setSize(size, size, false);
    renderer.render(scene, camera);

    const left = spec.x * W - size / 2, top = spec.y * H - size / 2;
    const box = { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity, screen: spec.screen };
    const positions = frame.attributes.position;
    for (let i = 0; i < positions.count; i++) {
      vertex.fromBufferAttribute(positions, i).applyMatrix4(phone.matrixWorld).project(camera);
      const x = left + (vertex.x + 1) / 2 * size, y = top + (1 - vertex.y) / 2 * size;
      box.left = Math.min(box.left, x); box.right = Math.max(box.right, x);
      box.top = Math.min(box.top, y); box.bottom = Math.max(box.bottom, y);
    }
    bounds.push(box);
    const image = new Image();
    image.src = renderer.domElement.toDataURL('image/png');
    await image.decode();
    Object.assign(image.style, { left: `${left}px`, top: `${top}px`, width: `${size}px`, height: `${size}px` });
    image.alt = spec.screen;
    layer.append(image);
  }
  renderer.dispose();

  // Shrink long translations until they fit their panel, clear the phones and break no word.
  await document.fonts.ready;
  for (const [index, section] of [...document.querySelectorAll('section')].entries()) {
    const slot = Number(section.dataset.slot);
    const problem = () => {
      const text = section.getBoundingClientRect();
      if (text.left < slot * W || text.right > (slot + 1) * W || text.bottom > H
          || [...section.children].some(line => line.scrollWidth > line.clientWidth)) return 'leaves its screenshot';
      const hit = bounds.find(b => b.left < text.right && b.right > text.left && b.top < text.bottom && b.bottom > text.top);
      return hit && `overlaps the ${hit.screen} phone`;
    };
    let size = 104;
    while (problem()) {
      if ((size -= 4) < 72) throw new Error(`Panel ${index + 1} text ${problem()} even at 76px`);
      section.style.fontSize = `${size}px`;
    }
  }
}

for (const locale of Object.keys(config.panels)) {
  // A fresh browser per locale: SwiftShader runs out of memory on the second wide strip otherwise.
  const browser = await chromium.launch({ headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  try {
    const count = config.panels[locale].length;
    const files = {};
    for (const { screen } of config.phones) {
      files[screen] = config.capture.replaceAll('{locale}', locale).replaceAll('{screen}', screen);
      const bytes = await readFile(path.join(captures, files[screen]));
      if (bytes.readUInt32BE(16) !== W || bytes.readUInt32BE(20) !== H) throw new Error(`Wrong capture size: ${files[screen]}`);
    }
    const tab = await browser.newPage({ viewport: { width: W * count, height: H }, deviceScaleFactor: 1 });
    const strip = layout(locale);
    await tab.route('http://render.local/**', async route => {
      const [scope, ...rest] = decodeURIComponent(new URL(route.request().url()).pathname).slice(1).split('/');
      const file = scope === 'three' ? path.join(threeDir, ...rest)
        : scope === 'capture' ? path.join(captures, ...rest)
        : scope.startsWith('font') ? path.resolve(path.dirname(configPath), config.font) : null;
      await route.fulfill(file
        ? { body: await readFile(file), contentType: types[path.extname(file)] }
        : { body: page(locale, strip), contentType: types['.html'] });
    });
    await tab.goto('http://render.local/');
    await tab.waitForFunction(() => window.lib);
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
