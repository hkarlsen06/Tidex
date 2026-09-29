'use client';

import { useEffect, useRef } from 'react';
import type { Locale } from '@/lib/i18n/config';

// The still and the model come from video/blender/phone3d.py --hero, which uses the same numbers: the phone rests
// turned a little toward the headline and fills FILL of the frame's height, seen through a 100 mm lens.
const REST = { pitch: 4, yaw: -10 };
const FILL = 0.86;
const PHONE_HEIGHT = 0.1634; // metres
const FOV = (2 * Math.atan(12 / 100) * 180) / Math.PI; // 24 mm sensor height at 100 mm
// Degrees the phone turns over the first SCROLL_RANGE screen heights of scrolling: its screen tips toward the
// bottom left.
const SCROLL = { pitch: 5, yaw: -12 };
const SCROLL_RANGE = 0.7;
// Degrees the phone turns toward the pointer, and how much of the gap to its target it closes per frame.
const REACH = { pitch: 8, yaw: 14 };
const EASE = 0.08;
// Pixels around the phone's box where it still follows the pointer. Further away it goes back to rest.
const NEAR = 48;

interface HeroPhoneProps {
  locale: Locale;
  alt: string;
  className?: string;
}

export function HeroPhone({ locale, alt, className = '' }: HeroPhoneProps) {
  const box = useRef<HTMLDivElement>(null);
  const still = useRef<HTMLImageElement>(null);

  useEffect(() => {
    // Reduced motion keeps the still and never downloads three.js or the model.
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const followsPointer = matchMedia('(hover: hover) and (pointer: fine)').matches;
    let cleanup = () => {};
    let cancelled = false;
    let started = false;

    // Nothing loads until the visitor first moves the mouse, touches or scrolls, so three.js stays off the page
    // load. The live phone starts at the still's angle and eases to where the scroll puts it, so the swap is quiet.
    const start = () => {
      if (started) return;
      started = true;
      triggers.forEach((type) => removeEventListener(type, start));
      load().catch(() => {
        // No WebGL or the model failed to load: the still stays.
      });
    };
    const triggers = ['pointermove', 'touchstart', 'scroll'] as const;
    triggers.forEach((type) => addEventListener(type, start, { passive: true }));

    const load = async () => {
      const [THREE, { GLTFLoader }, { RoomEnvironment }] = await Promise.all([
        import('three'),
        import('three/examples/jsm/loaders/GLTFLoader.js'),
        import('three/examples/jsm/environments/RoomEnvironment.js'),
      ]);
      const gltf = await new GLTFLoader().loadAsync(`/story/${locale}/phone.glb`);
      const element = box.current;
      if (cancelled || !element) return;

      const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
      renderer.setClearColor(0, 0);
      // Blender's Standard view transform: no tone mapping, so the screen keeps the capture's colours.
      renderer.toneMapping = THREE.NoToneMapping;
      const canvas = renderer.domElement;
      canvas.className = 'absolute inset-0 h-full w-full opacity-0 transition-opacity duration-500';
      element.append(canvas);

      // Stand-in for the film's studio: a soft room for the reflections, a white key and two blue rims.
      const scene = new THREE.Scene();
      const pmrem = new THREE.PMREMGenerator(renderer);
      scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
      scene.environmentIntensity = 0.35;
      for (const [color, intensity, x, y, z] of [
        ['#ffffff', 2.2, -0.8, 0.9, 1.0],
        ['#5b86ff', 5, 0.75, 0.25, -0.55],
        ['#8fb0ff', 2.5, -0.8, 0.1, -0.5],
        ['#ffffff', 0.8, 0.1, 1.1, 0.2],
      ] as const) {
        const light = new THREE.DirectionalLight(color, intensity);
        light.position.set(x, y, z);
        scene.add(light);
      }
      const phone = new THREE.Group();
      phone.add(gltf.scene);
      scene.add(phone);

      const camera = new THREE.PerspectiveCamera(FOV, 0.5, 0.01, 10);
      camera.position.z = PHONE_HEIGHT / FILL / 0.24;

      const rad = THREE.MathUtils.degToRad;
      const turn = { ...REST };
      const target = { ...REST };
      const pointer = { pitch: 0, yaw: 0 };
      let frame = 0;
      const render = () => {
        phone.rotation.set(rad(turn.pitch), rad(turn.yaw), 0, 'YXZ');
        renderer.render(scene, camera);
      };
      const step = () => {
        turn.pitch += (target.pitch - turn.pitch) * EASE;
        turn.yaw += (target.yaw - turn.yaw) * EASE;
        render();
        const settled =
          Math.abs(target.pitch - turn.pitch) < 0.01 && Math.abs(target.yaw - turn.yaw) < 0.01;
        frame = settled ? 0 : requestAnimationFrame(step);
      };
      // The target is the resting angle, plus the scroll turn, plus the pull toward the pointer.
      const retarget = () => {
        const scrolled = Math.min(1, Math.max(0, scrollY / (innerHeight * SCROLL_RANGE)));
        target.pitch = REST.pitch + scrolled * SCROLL.pitch + pointer.pitch;
        target.yaw = REST.yaw + scrolled * SCROLL.yaw + pointer.yaw;
        if (!frame) frame = requestAnimationFrame(step);
      };
      // Over the phone or within NEAR of it, the screen turns toward the pointer: fully at the edge of that area,
      // not at all at the centre.
      const onMove = (event: PointerEvent) => {
        const rect = element.getBoundingClientRect();
        const x = (event.clientX - rect.left - rect.width / 2) / (rect.width / 2 + NEAR);
        const y = (event.clientY - rect.top - rect.height / 2) / (rect.height / 2 + NEAR);
        const near = Math.abs(x) <= 1 && Math.abs(y) <= 1;
        pointer.pitch = near ? y * REACH.pitch : 0;
        pointer.yaw = near ? x * REACH.yaw : 0;
        retarget();
      };
      const onLeave = () => {
        pointer.pitch = pointer.yaw = 0;
        retarget();
      };

      const resize = () => {
        renderer.setSize(element.clientWidth, element.clientHeight, false);
        camera.aspect = element.clientWidth / element.clientHeight;
        camera.updateProjectionMatrix();
        render();
      };
      const observer = new ResizeObserver(resize);
      observer.observe(element);
      resize();
      canvas.classList.replace('opacity-0', 'opacity-100');
      still.current?.classList.add('opacity-0');
      retarget();
      addEventListener('scroll', retarget, { passive: true });
      if (followsPointer) {
        addEventListener('pointermove', onMove);
        document.documentElement.addEventListener('pointerleave', onLeave);
      }

      cleanup = () => {
        cancelAnimationFrame(frame);
        observer.disconnect();
        removeEventListener('scroll', retarget);
        removeEventListener('pointermove', onMove);
        document.documentElement.removeEventListener('pointerleave', onLeave);
        pmrem.dispose();
        renderer.dispose();
        canvas.remove();
        still.current?.classList.remove('opacity-0');
      };
    };

    return () => {
      cancelled = true;
      triggers.forEach((type) => removeEventListener(type, start));
      cleanup();
    };
  }, [locale]);

  return (
    <div ref={box} className={`relative aspect-[1/2] ${className}`}>
      <img
        ref={still}
        src={`/story/${locale}/phone.webp`}
        alt={alt}
        width={800}
        height={1600}
        fetchPriority="high"
        className="h-full w-full object-contain transition-opacity duration-500"
      />
    </div>
  );
}
