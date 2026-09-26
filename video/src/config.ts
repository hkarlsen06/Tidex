import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";
import { loadFont as loadPoppins } from "@remotion/google-fonts/Poppins";

export type Lang = "en" | "no";
export type Variant = "social" | "appstore";
// [x1, y1, x2, y2] as fractions of the app screen.
export type Box = [number, number, number, number];

export const FPS = 30;
// Timeline blocks line up with the 120 BPM bars in scripts/make-audio.mjs (60 frames per bar).
export const HOOK = 120;
export const OUTRO = 120;

export const SANS = loadPoppins("normal", { weights: ["500", "600", "700"], subsets: ["latin", "latin-ext"] }).fontFamily;
export const MONO = loadMono("normal", { weights: ["500", "700"], subsets: ["latin", "latin-ext"] }).fontFamily;

// DESIGN.md tokens, plus the app icon blue.
export const C = {
  bg: "#060B16",
  blue: "#2563EB",
  blueBright: "#4C86EA",
  indigo: "#4338CA",
  green: "#22C55E",
  text: "#F2F7FC",
  text2: "#C6D7E6",
  muted: "#9DB4C8",
  paperInk: "#0B1526",
  paperMuted: "#5B6B80",
  paperRed: "#C81E1E",
};

// iPhone 17 Pro Max captures are 1320 x 2868.
export const SCREEN_RATIO = 2868 / 1320;

export const layout = (width: number) =>
  width >= 1000
    ? { cardW: 640, cardX: 220, cardY: 470, capTop: 118, capBottom: 438, capSize: 80 }
    : { cardW: 660, cardX: 113, cardY: 396, capTop: 80, capBottom: 362, capSize: 66 };

// Braces mark the highlighted words, "\n" marks a line break.
export const COPY = {
  en: {
    hook: "What's that\nextra shift\nreally {worth?}",
    shift: "Saturday shift",
    shiftPay: "1,600 kr",
    afterTax: "after tax",
    captions: {
      home: "Know what\n{payday} brings",
      payroll: "See how your\n{pay adds up}",
      stats: "Follow your\nearnings {over time}",
      add: "Calculate pay\nfor {every shift}",
      wagey: "Ask {anything}\nabout your shifts",
    },
    receipt: [
      ["Base pay", "25,200 kr"],
      ["Supplement", "+2,800 kr"],
      ["Gross", "28,000 kr"],
      ["Estimated tax", "−5,600 kr"],
      ["Net", "22,400 kr"],
    ],
    tagline: "Know what your\n{shift is worth}",
    cta: "Free to start",
    disclaimer: "Account required. Some features require\na subscription or in-app purchase.",
  },
  no: {
    hook: "Hva er den\nekstravakten\negentlig {verdt?}",
    shift: "Lørdagsvakt",
    shiftPay: "1 600 kr",
    afterTax: "etter skatt",
    captions: {
      home: "Se hva du får\npå {lønningsdagen}",
      payroll: "Se hvordan\n{lønnen regnes ut}",
      stats: "Følg inntekten\n{over tid}",
      add: "Beregn lønn\nfor {hver vakt}",
      wagey: "Spør om {alt}\nrundt vaktene dine",
    },
    receipt: [
      ["Grunnlønn", "25 200 kr"],
      ["Tillegg", "+2 800 kr"],
      ["Brutto", "28 000 kr"],
      ["Beregnet skatt", "−5 600 kr"],
      ["Netto", "22 400 kr"],
    ],
    tagline: "Se hva vakten\ndin er {verdt}",
    cta: "Gratis å starte",
    disclaimer: "Krever konto. Noen funksjoner krever\nabonnement eller kjøp i appen.",
  },
} as const;

type Tap = { src: number; x: number; y: number; drag?: { srcStart: number; srcEnd: number; x: number; y: number } };
type Lift = { box: Box; at: number; until: number; scale: number; to: [number, number]; rotate: number };

// A footage range, or a rebuilt sheet slide: the simulator stalled while the UI test dragged the payroll
// sheet up, so the slide moves the settled sheet (frame b + 2) over the medium-detent frame (a - 1).
export type Piece = [number, number] | { slide: [number, number]; frames: number };

// Payroll sheet geometry in the 900 x 1956 clips. At the medium detent the sheet floats: it is the settled
// sheet scaled to 0.9687, 13.5 px in from each side and 13 px above the bottom, with rounder bottom corners.
export const SHEET = {
  medium: 918 / 1956,
  large: 127 / 1956,
  mediumScale: 0.9687,
  bottomInset: 13 / 1956,
  radius: 78 / 900,
  bottomRadius: 110 / 900,
  statusBar: 110 / 1956,
};
const GRAB_Y = 0.515;

export type SceneId = keyof (typeof COPY)["en"]["captions"];
export type Scene = {
  id: SceneId;
  duration: number;
  // Crossfade frames from the previous footage; 0 where the recording is continuous.
  fadeIn: number;
  // Ranges of footage frames (public/footage/<lang>.mp4, 30 fps) played back to back, then held.
  pieces: Record<Lang, Piece[]>;
  taps: Record<Lang, Tap[]>;
  lifts: Record<Lang, Lift[]>;
  // Extra sound effects [file, scene frame]; taps and lifts add their own.
  sfx: [string, number][];
};

const TAB_Y = 0.947;
const payout: Lift = { box: [0.05, 0.555, 0.95, 0.645], at: 30, until: 98, scale: 1.3, to: [0, -0.05], rotate: -2 };
const addTotal: Lift = { box: [0.74, 0.058, 0.975, 0.112], at: 76, until: 116, scale: 2.1, to: [-0.36, 0.1], rotate: 3 };
const answer: Lift = { box: [0.03, 0.192, 0.87, 0.338], at: 38, until: 114, scale: 1.18, to: [0.02, 0.12], rotate: -1.5 };

// Frame numbers come from the recorded UI-test walkthrough (see README).
export const SCENES: Scene[] = [
  {
    id: "home",
    duration: 105,
    fadeIn: 0,
    pieces: { en: [[24, 144]], no: [[20, 140]] },
    taps: { en: [], no: [] },
    lifts: { en: [payout], no: [payout] },
    sfx: [],
  },
  {
    id: "payroll",
    duration: 180,
    fadeIn: 0,
    pieces: {
      en: [[376, 404], [450, 470], [494, 500], { slide: [500, 526], frames: 16 }, [526, 532]],
      no: [[157, 185], [230, 252], [272, 279], { slide: [279, 306], frames: 16 }, [306, 312]],
    },
    taps: {
      en: [
        { src: 381, x: 0.19, y: 0.575 },
        { src: 453, x: 0.26, y: 0.685 },
        { src: 496, x: 0.66, y: GRAB_Y, drag: { srcStart: 500, srcEnd: 526, x: 0.66, y: GRAB_Y - SHEET.medium + SHEET.large } },
      ],
      no: [
        { src: 162, x: 0.21, y: 0.575 },
        { src: 233, x: 0.24, y: 0.685 },
        { src: 275, x: 0.66, y: GRAB_Y, drag: { srcStart: 279, srcEnd: 306, x: 0.66, y: GRAB_Y - SHEET.medium + SHEET.large } },
      ],
    },
    lifts: { en: [], no: [] },
    sfx: [],
  },
  {
    id: "stats",
    duration: 75,
    fadeIn: 8,
    pieces: { en: [[720, 810]], no: [[505, 595]] },
    taps: { en: [], no: [] },
    lifts: {
      en: [{ box: [0.07, 0.34, 0.7, 0.382], at: 12, until: 70, scale: 1.45, to: [0.08, 0.06], rotate: -2 }],
      no: [{ box: [0.07, 0.34, 0.52, 0.382], at: 12, until: 70, scale: 1.6, to: [0.12, 0.06], rotate: -2 }],
    },
    sfx: [],
  },
  {
    id: "add",
    duration: 120,
    fadeIn: 8,
    pieces: { en: [[975, 1015], [1152, 1232]], no: [[763, 883]] },
    taps: {
      en: [{ src: 975, x: 0.5, y: TAB_Y }, { src: 1164, x: 0.31, y: 0.752 }],
      no: [{ src: 763, x: 0.5, y: TAB_Y }],
    },
    lifts: { en: [addTotal], no: [{ ...addTotal, at: 40, until: 116 }] },
    sfx: [],
  },
  {
    id: "wagey",
    duration: 120,
    fadeIn: 0,
    pieces: { en: [[1262, 1382]], no: [[976, 1096]] },
    taps: { en: [{ src: 1266, x: 0.672, y: TAB_Y }], no: [{ src: 980, x: 0.672, y: TAB_Y }] },
    lifts: {
      en: [{ box: [0.355, 0.14, 0.965, 0.19], at: 26, until: 114, scale: 1.2, to: [-0.02, 0.0], rotate: 2 }, answer],
      no: [{ box: [0.235, 0.14, 0.965, 0.19], at: 26, until: 114, scale: 1.16, to: [-0.02, 0.0], rotate: 2 }, answer],
    },
    sfx: [["sparkle", 44]],
  },
];

// The payroll receipt prints over the held payroll sheet, in scene frames. It starts on the bar 5 downbeat of
// the music so the hi-hat roll in scripts/make-audio.mjs lands its last row on the bar 6 downbeat.
export const RECEIPT_AT = 75;

export const FEATURES = SCENES.reduce((sum, scene) => sum + scene.duration, 0);
export const totalFrames = (variant: Variant) => (variant === "social" ? HOOK : 0) + FEATURES + OUTRO;
