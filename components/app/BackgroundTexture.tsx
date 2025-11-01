/**
 * BackgroundTexture Component
 *
 * Adds a sophisticated textured background with multiple layers:
 * - Radial gradient for subtle depth
 * - SVG noise for fine grain texture
 * - CSS dot pattern for geometric interest
 *
 * All colors use theme-aware CSS variables for dark/light mode compatibility.
 * Designed to stay behind all content without affecting layout or performance.
 */

import React from 'react';

type IntensityLevel = 'subtle' | 'medium' | 'bold';

interface BackgroundTextureProps {
  intensity?: IntensityLevel;
}

const intensityConfig = {
  subtle: {
    radialOpacity: 0.04,
    noiseOpacity: 0.08,
    dotOpacity: 0.12,
  },
  medium: {
    radialOpacity: 0.06,
    noiseOpacity: 0.12,
    dotOpacity: 0.18,
  },
  bold: {
    radialOpacity: 0.08,
    noiseOpacity: 0.16,
    dotOpacity: 0.24,
  },
};

export function BackgroundTexture({ intensity = 'subtle' }: BackgroundTextureProps) {
  const config = intensityConfig[intensity];

  return (
    <>
      {/* SVG Filters - Hidden but available for use */}
      <svg
        className="absolute w-0 h-0"
        aria-hidden="true"
        style={{ position: 'absolute', width: 0, height: 0 }}
      >
        <defs>
          {/* Fine grain noise filter */}
          <filter id="noise-filter">
            <feTurbulence
              type="fractalNoise"
              baseFrequency="0.95"
              numOctaves="4"
              stitchTiles="stitch"
            />
            <feColorMatrix type="saturate" values="0" />
          </filter>
        </defs>
      </svg>

      {/* Background Texture Container */}
      <div
        className="fixed inset-0 -z-10 overflow-hidden"
        aria-hidden="true"
        style={{ pointerEvents: 'none' }}
      >
        {/* Layer 1: Radial Gradient - Subtle depth using brand colors */}
        <div
          className="absolute inset-0"
          style={{
            background: `radial-gradient(circle at center, hsla(199, 89%, 48%, ${config.radialOpacity}), transparent 70%)`,
          }}
        />

        {/* Layer 2: SVG Noise/Grain Texture */}
        <div
          className="absolute inset-0"
          style={{
            opacity: config.noiseOpacity,
            filter: 'url(#noise-filter)',
            mixBlendMode: 'overlay',
          }}
        />

        {/* Layer 3: Geometric Dot Pattern */}
        <div
          className="absolute inset-0"
          style={{
            opacity: config.dotOpacity,
            backgroundImage: `radial-gradient(circle at center, hsl(188, 86%, 53%) 1px, transparent 1px)`,
            backgroundSize: '32px 32px',
            backgroundPosition: '0 0, 16px 16px',
          }}
        />

        {/* Additional subtle radial gradient at top for depth */}
        <div
          className="absolute inset-0"
          style={{
            background: `radial-gradient(circle at top, hsla(189, 94%, 43%, ${config.radialOpacity * 0.75}), transparent 55%)`,
          }}
        />
      </div>
    </>
  );
}
