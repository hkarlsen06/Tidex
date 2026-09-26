import React from "react";

// Geometry from marketing/public/brand/tidex-mark.svg, moved to the ruler's top-left corner.
// The ruler is 612 x 162; its nine notches mark an 8-hour shift (long notches at 0, 4 and 8 h).
export const RULER_W = 612;
export const RULER_H = 162;
export const NOTCHES = [90, 144, 198, 252, 306, 360, 414, 468, 522];
export const RULER_PATH =
  "M 81 0 L 82 0 L 82 48 A 8 8 0 0 0 98 48 L 98 0 L 136 0 L 136 16 A 8 8 0 0 0 152 16 L 152 0 " +
  "L 190 0 L 190 16 A 8 8 0 0 0 206 16 L 206 0 L 244 0 L 244 16 A 8 8 0 0 0 260 16 L 260 0 " +
  "L 298 0 L 298 48 A 8 8 0 0 0 314 48 L 314 0 L 352 0 L 352 16 A 8 8 0 0 0 368 16 L 368 0 " +
  "L 406 0 L 406 16 A 8 8 0 0 0 422 16 L 422 0 L 460 0 L 460 16 A 8 8 0 0 0 476 16 L 476 0 " +
  "L 514 0 L 514 48 A 8 8 0 0 0 530 48 L 530 0 L 531 0 A 81 81 0 0 1 531 162 L 81 162 A 81 81 0 0 1 81 0 Z";

// The payslip sits 154 right of and 184 below the ruler origin; 304 wide, a 396 body and a 60-deep torn edge.
export const SLIP = { x: 154, y: 184, w: 304, body: 396, teeth: 60 };

// Payslip outline with a variable body height and horizontal stretch; the torn edge keeps its depth.
export const slipPath = (body: number, sx = 1) => {
  const x = (v: number) => (v * sx).toFixed(2);
  const y = (v: number) => (v - 396 + body).toFixed(2);
  const pts = [
    [304, 406, 297.9, 414], [272.1, 448], [266, 456, 259.9, 448], [234.1, 414], [228, 406, 221.9, 414],
    [196.1, 448], [190, 456, 183.9, 448], [158.1, 414], [152, 406, 145.9, 414], [120.1, 448],
    [114, 456, 107.9, 448], [82.1, 414], [76, 406, 69.9, 414], [44.1, 448], [38, 456, 31.9, 448],
    [6.1, 414], [0, 406, 0, 396],
  ];
  const edge = pts
    .map((p) => (p.length === 4 ? `Q ${x(p[0])} ${y(p[1])} ${x(p[2])} ${y(p[3])}` : `L ${x(p[0])} ${y(p[1])}`))
    .join(" ");
  return `M 0 0 L ${x(304)} 0 L ${x(304)} ${y(396)} ${edge} Z`;
};

// Where the mark sits inside the exported app icon (tidex-app-icon.png), per pixel of icon size.
export const ICON_MARK = { x: 0.2251, y: 0.2107, scale: 0.46 / 512 };

const LETTERS = [
  "M7 0 H71 Q77 0 77 6 V12 Q77 18 71 18 H48 V90.4 Q48 92 47.07 93.3 L43.93 97.7 Q43 99 42.07 97.7 L38.93 93.3 Q38 92 37.07 93.3 L33.93 97.7 Q33 99 32.07 97.7 L28.93 93.3 Q28 92 28 90.4 V18 H7 Q1 18 1 12 V6 Q1 0 7 0 Z",
  "M91.5 0 H97.5 Q104 0 104 6.5 V12.5 Q104 19 97.5 19 H91.5 Q85 19 85 12.5 V6.5 Q85 0 91.5 0 Z M91.5 29 H97.5 Q104 29 104 35.5 V94.5 Q104 101 97.5 101 H91.5 Q85 101 85 94.5 V35.5 Q85 29 91.5 29 Z",
  "M146 26 C126 26 114 40 114 64 C114 88 126 102 146 102 C156 102 164 98 169 91 V95 Q169 101 175 101 H181 Q187 101 187 95 V6 Q187 0 181 0 H175 Q169 0 169 6 V36 C163 29 156 26 146 26 Z M149 43 C137 43 133 51 133 64 C133 77 138 85 149 85 C161 85 168 77 168 64 C168 51 161 43 149 43 Z",
  "M234 26 C211 26 197 41 197 64 C197 88 212 102 236 102 C248 102 258 98 265 91 Q268 88 265 85 L259 79 Q257 77 254 79 C249 83 244 86 236 86 C224 86 217 80 216 70 H262 Q267 70 267 65 V62 C267 40 254 26 234 26 Z M216 56 C218 46 224 41 234 41 C244 41 250 46 250 56 Z",
  "M270 30 Q267 26 273 26 H286 Q290 26 292 30 L306 51 L321 30 Q323 26 327 26 H338 Q343 26 340 31 L317 63 L340 97 Q343 101 338 101 H324 Q320 101 318 97 L304 75 L289 97 Q287 101 283 101 H271 Q266 101 269 97 L292 64 Z",
];

// The Tidex lettering; `progress(i)` returns 0..1 for each of the five letters.
export const Wordmark: React.FC<{ height: number; color?: string; progress: (i: number) => number }> = ({
  height,
  color = "#FFFFFF",
  progress,
}) => (
  <svg width={(height * 345) / 106} height={height} viewBox="0 0 345 106" style={{ overflow: "visible" }}>
    <g transform="translate(2 2)" fill={color}>
      {LETTERS.map((d, i) => {
        const p = progress(i);
        return (
          <path
            key={i}
            d={d}
            fillRule="evenodd"
            opacity={Math.min(1, p * 2)}
            transform={`translate(0 ${(1 - p) * 40})`}
          />
        );
      })}
    </g>
  </svg>
);
