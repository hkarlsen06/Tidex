# Marketing Landing Page

A static Next.js landing page for the kkarlsen.dev wage calculator application.

## Features

- ✅ Next.js 15 with static export
- ✅ shadcn/ui components (Button, Accordion)
- ✅ Tailwind CSS for styling
- ✅ Responsive design (mobile-first)
- ✅ Dark theme with gradient animations
- ✅ Norwegian language content
- ✅ SEO optimized with metadata
- ✅ Static HTML/CSS/JS output to `dist/` folder

## Getting Started

### Install Dependencies

```bash
npm install
```

### Development

Run the development server:

```bash
npm run dev
```

Open [http://localhost:3001](http://localhost:3001) to view the landing page.

### Build for Production

Build the static site:

```bash
npm run build
```

This will generate static HTML, CSS, and JS files in the `dist/` folder, ready to be deployed to Netlify or any static hosting service.

### Preview Production Build

```bash
npm run start
```

## Deployment

The `dist/` folder contains all the static files needed for deployment. Simply upload the contents to your hosting provider (e.g., Netlify, Vercel, GitHub Pages).

For Netlify:
- Build command: `npm run build`
- Publish directory: `dist`

## Structure

```
marketing/
├── app/
│   ├── layout.tsx         # Root layout with metadata
│   ├── page.tsx          # Landing page component
│   └── globals.css       # Global styles + Tailwind
├── components/
│   └── ui/               # shadcn components
│       ├── button.tsx
│       └── accordion.tsx
├── lib/
│   └── utils.ts          # Utility functions (cn)
├── public/               # Static assets
│   ├── demo.gif
│   ├── favicon.ico
│   └── ...
├── dist/                 # Build output (gitignored)
├── next.config.js        # Next.js config (static export)
├── tailwind.config.ts    # Tailwind configuration
├── tsconfig.json         # TypeScript config
└── package.json
```

## Key Changes from Vite Version

- Migrated from Vite to Next.js 15
- Using shadcn/ui components instead of custom HTML
- App redirect updated: `kalkulator.kkarlsen.dev` → `app.kkarlsen.dev`
- Static export configured to output to `dist/` folder
- Improved component architecture and accessibility
