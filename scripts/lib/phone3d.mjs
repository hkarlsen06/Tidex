// 3D iPhone 17 Pro Max model shared by the App Store screenshot and creative asset renderers.
// WebGL runs on SwiftShader, so reruns match to within a few levels per channel.
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';

const threeDir = path.resolve(createRequire(import.meta.url).resolve('three'), '../..');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf' };

export const launch = chromium =>
  chromium.launch({ headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });

// Put this in the page's HTML so renderPhones can reach three.js.
export const threeImports = `
    <script type="importmap">{"imports":{"three":"/three/build/three.module.js","three/addons/":"/three/examples/jsm/"}}</script>
    <script type="module">
      import * as THREE from 'three';
      import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
      import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
      import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
      window.lib = { THREE, RoomEnvironment, RoundedBoxGeometry, mergeVertices };
    </script>`;

// Opens a page of the given size that serves html at /, three.js, captures under /capture/ and the font under /font.
export async function openPage(browser, { width, height, html, captures, font }) {
  const tab = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  await tab.route('http://render.local/**', async route => {
    const [scope, ...rest] = decodeURIComponent(new URL(route.request().url()).pathname).slice(1).split('/');
    const file = scope === 'three' ? path.join(threeDir, ...rest)
      : scope === 'capture' ? path.join(captures, ...rest)
      : scope.startsWith('font') && font ? font : null;
    await route.fulfill(file
      ? { body: await readFile(file), contentType: types[path.extname(file)] }
      : { body: html, contentType: types['.html'] });
  });
  await tab.goto('http://render.local/');
  await tab.waitForFunction(() => window.lib);
  return tab;
}

// Runs in the page. Builds one phone model, renders each capture on it into its own transparent
// canvas and places that canvas on the strip. W and H are the size of one panel; spec.x, spec.y and
// spec.height are fractions of it. Returns nothing; throws if the layout is broken.
export async function renderPhones({ phones, finish, W, H, captures }) {
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
    const cw = capture.naturalWidth, ch = capture.naturalHeight;
    const x0 = (canvas.width - cw) / 2, y0 = (canvas.height - ch) / 2;
    c.fillStyle = '#030304';
    c.fillRect(0, 0, canvas.width, canvas.height);
    c.save();
    c.beginPath();
    c.roundRect(x0, y0, cw, ch, 186);
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
