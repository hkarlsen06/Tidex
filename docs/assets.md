# UI Assets

## Icons

- All SVG icons originate from the [Tabler Icons](https://tablericons.com/) collection.
- Raw SVGs are committed under `app/src/icons` so we can tweak fill, stroke, or sizing without relying on the CDN.
- When you introduce a new icon, export it from Tabler (matching the 24×24 outline or filled variant we use) and drop the optimized SVG into that folder.
- React components can import the matching `@tabler/icons-react` symbol when inline rendering is easier than referencing the raw SVG.

Keeping the sources consistent makes it easy to refresh assets or swap variants while staying visually cohesive.
