#!/usr/bin/env node

/**
 * Generate iOS splash screen images
 * Creates simple splash screens with centered logo and background color
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const splashDir = path.join(__dirname, '..', 'public', 'splash');
const backgroundColor = '#0c0e14'; // Dark background from manifest
const foregroundColor = '#ffffff'; // White for text/logo

// iOS splash screen sizes (width x height)
const splashSizes = [
  { name: 'apple-splash-1170-2532', width: 1170, height: 2532 }, // iPhone 14 Pro
  { name: 'apple-splash-2532-1170', width: 2532, height: 1170 }, // iPhone 14 Pro landscape
  { name: 'apple-splash-1284-2778', width: 1284, height: 2778 }, // iPhone 14 Plus
  { name: 'apple-splash-2778-1284', width: 2778, height: 1284 }, // iPhone 14 Plus landscape
  { name: 'apple-splash-1125-2436', width: 1125, height: 2436 }, // iPhone X/11 Pro
  { name: 'apple-splash-2436-1125', width: 2436, height: 1125 }, // iPhone X/11 Pro landscape
  { name: 'apple-splash-1242-2208', width: 1242, height: 2208 }, // iPhone 8 Plus
  { name: 'apple-splash-2208-1242', width: 2208, height: 1242 }, // iPhone 8 Plus landscape
  { name: 'apple-splash-750-1334', width: 750, height: 1334 },   // iPhone 8
  { name: 'apple-splash-1334-750', width: 1334, height: 750 },   // iPhone 8 landscape
  { name: 'apple-splash-2048-2732', width: 2048, height: 2732 }, // iPad Pro 12.9"
  { name: 'apple-splash-2732-2048', width: 2732, height: 2048 }, // iPad Pro 12.9" landscape
  { name: 'apple-splash-1668-2388', width: 1668, height: 2388 }, // iPad Pro 11"
  { name: 'apple-splash-2388-1668', width: 2388, height: 1668 }, // iPad Pro 11" landscape
  { name: 'apple-splash-1640-2360', width: 1640, height: 2360 }, // iPad Air
  { name: 'apple-splash-2360-1640', width: 2360, height: 1640 }, // iPad Air landscape
  { name: 'apple-splash-1620-2160', width: 1620, height: 2160 }, // iPad 10.2"
  { name: 'apple-splash-2160-1620', width: 2160, height: 1620 }, // iPad 10.2" landscape
];

/**
 * Generate SVG splash screen
 */
function generateSVG(width, height) {
  const logoSize = Math.min(width, height) * 0.2; // Logo is 20% of smallest dimension
  const logoX = (width - logoSize) / 2;
  const logoY = (height - logoSize) / 2 - logoSize * 0.2; // Slightly above center

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
  <!-- Background -->
  <rect width="${width}" height="${height}" fill="${backgroundColor}"/>

  <!-- Logo placeholder - centered circle with app initial -->
  <circle cx="${width / 2}" cy="${logoY + logoSize / 2}" r="${logoSize / 2}" fill="${foregroundColor}" opacity="0.1"/>
  <text x="${width / 2}" y="${logoY + logoSize / 2}"
        font-family="system-ui, -apple-system, sans-serif"
        font-size="${logoSize * 0.6}"
        font-weight="bold"
        fill="${foregroundColor}"
        text-anchor="middle"
        dominant-baseline="central">T</text>

  <!-- App name -->
  <text x="${width / 2}" y="${logoY + logoSize + logoSize * 0.4}"
        font-family="system-ui, -apple-system, sans-serif"
        font-size="${logoSize * 0.15}"
        font-weight="600"
        fill="${foregroundColor}"
        text-anchor="middle"
        dominant-baseline="hanging">Tidex</text>
</svg>`;
}

/**
 * Main function to generate all splash screens
 */
async function generateSplashScreens() {
  console.log('🎨 Generating iOS splash screens...\n');

  // Ensure splash directory exists
  if (!fs.existsSync(splashDir)) {
    fs.mkdirSync(splashDir, { recursive: true });
  }

  // Generate each splash screen
  for (const size of splashSizes) {
    const svg = generateSVG(size.width, size.height);
    const svgPath = path.join(splashDir, `${size.name}.svg`);

    fs.writeFileSync(svgPath, svg);
    console.log(`✓ Generated ${size.name}.svg (${size.width}x${size.height})`);
  }

  console.log('\n✨ All splash screens generated successfully!');
  console.log('\n⚠️  Note: These are SVG placeholders. For production, consider:');
  console.log('   1. Converting to PNG using sharp or ImageMagick');
  console.log('   2. Using your actual app logo/icon');
  console.log('   3. Optimizing file sizes for faster loading');
  console.log('\n💡 SVGs work on iOS 13+ but PNGs are more compatible.');
}

// Run the script
generateSplashScreens().catch(console.error);
